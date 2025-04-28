// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

/**
 * @notice Helper contract to simulate execution results from STEX AMM.
 */
contract STEXLens {
    /**
     *
     *  CUSTOM INTERNAL STRUCTS
     *
     */
    struct WithdrawCache {
        uint256 totalSupply;
        uint256 reserve0Pool;
        uint256 reserve1Pool;
        uint256 amount1LendingPool;
        uint256 instantWithdrawalFee1;
        uint256 amount1Remaining;
    }

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant BIPS = 1e4;

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function getAllReserves(address stex)
        external
        view
        returns (
            uint256 reserve0Pool,
            uint256 reserve0Unstaking,
            uint256 reserve1Pool,
            uint256 reserve1Lending,
            uint256 amount1PendingLPWithdrawal
        )
    {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        IWithdrawalModule withdrawalModule = IWithdrawalModule(stexInterface.withdrawalModule());

        (reserve0Pool, reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();

        reserve0Unstaking = withdrawalModule.amountToken0PendingUnstaking();

        reserve1Lending = withdrawalModule.amountToken1LendingPool();

        amount1PendingLPWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
    }

    function getSharesForDeposit(address stex, uint256 amount) external view returns (uint256) {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();
        return _getSharesForDeposit(stex, amount, reserve0Pool, reserve1Pool);
    }

    function getSharesForDepositAndPoolReserves(
        address stex,
        uint256 amount,
        uint256 reserve0Pool,
        uint256 reserve1Pool
    ) external view returns (uint256) {
        return _getSharesForDeposit(stex, amount, reserve0Pool, reserve1Pool);
    }

    function getMinAmountsForToken0Deposit(
        address stex,
        uint256 amountToken0,
        uint256 slippageSwapBips,
        uint256 slippageDepositBips
    ) external view returns (uint256 amountToken1Min, uint256 minShares) {
        ISTEXAMM stexInterface = ISTEXAMM(stex);

        (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();

        uint256 amountToken1 = stexInterface.getAmountOut(stexInterface.token0(), amountToken0, false);
        require(amountToken1 <= reserve1Pool, "Excessive swap amount");

        amountToken1Min = (amountToken1 * (BIPS - slippageSwapBips)) / BIPS;

        reserve0Pool += amountToken0;
        reserve1Pool -= amountToken1Min;

        uint256 shares = _getSharesForDeposit(stex, amountToken1Min, reserve0Pool, reserve1Pool);

        minShares = (shares * (BIPS - slippageDepositBips)) / BIPS;
    }

    function getAmountsForWithdraw(address stex, uint256 shares, bool isInstantWithdrawal)
        external
        view
        returns (uint256, uint256)
    {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        uint256 totalSupplyCache = ERC20(stex).totalSupply();
        if (totalSupplyCache == 0) {
            return (0, 0);
        }
        uint256 amount0;
        uint256 amount1;
        IWithdrawalModule withdrawalModule = IWithdrawalModule(stexInterface.withdrawalModule());

        WithdrawCache memory cache;

        (cache.reserve0Pool, cache.reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();
        cache.totalSupply = totalSupplyCache;

        {
            uint256 amountToken0PendingUnstaking = withdrawalModule.amountToken0PendingUnstaking();
            uint256 reserve0PendingWithdrawal =
                withdrawalModule.convertToToken0(withdrawalModule.amountToken1PendingLPWithdrawal());

            uint256 amount0Deduction;
            if (cache.reserve0Pool + amountToken0PendingUnstaking > reserve0PendingWithdrawal) {
                // pro-rata share of token0 reserves in pool (liquid), token0 reserves pending in withdrawal queue (locked)
                // minus token0 amount already owed to pending LP withdrawals.
                amount0 = Math.mulDiv(
                    cache.reserve0Pool + amountToken0PendingUnstaking - reserve0PendingWithdrawal,
                    shares,
                    cache.totalSupply
                );
            } else {
                // In this case there is more token0 owed to pending LP withdrawals,
                // but not enough token0 in pool reserves nor pending unstaking.
                // To ensure solvency of pending LP withdrawals,
                // this amount will be deducted from the user's token1 total amount (`amount1`)
                amount0Deduction = Math.mulDiv(
                    reserve0PendingWithdrawal - cache.reserve0Pool - amountToken0PendingUnstaking,
                    shares,
                    cache.totalSupply,
                    Math.Rounding.Ceil
                );
            }

            cache.amount1LendingPool =
                Math.mulDiv(withdrawalModule.amountToken1LendingPool(), shares, cache.totalSupply);
            // token1 amount calculated as pro-rata share of token1 reserves in the pool (liquid)
            // plus pro-rata share of token1 reserves earning yield in lending pool (liquid, assuming lending pool allows for instant withdrawals)
            amount1 = cache.amount1LendingPool + Math.mulDiv(cache.reserve1Pool, shares, cache.totalSupply);
            if (amount0Deduction > 0) {
                // Deduct this amount from token1, as it needs to be held to honor pending LP withdrawals
                uint256 amount1Deduction = withdrawalModule.convertToToken1(amount0Deduction);
                amount1 = amount1 > amount1Deduction ? amount1 - amount1Deduction : 0;
            }
        }

        if (isInstantWithdrawal) {
            uint256 amount1SwapEquivalent = stexInterface.getAmountOut(stexInterface.token0(), amount0, true);
            // Apply manager fee on instant withdrawals in token1
            uint256 amount1WithFee = withdrawalModule.convertToToken1(amount0);
            cache.instantWithdrawalFee1 = (
                (amount1WithFee - amount1SwapEquivalent) * ISovereignPool(stexInterface.pool()).poolManagerFeeBips()
            ) / BIPS;
            amount1 += amount1SwapEquivalent;

            amount0 = 0;
        }

        return (amount0, amount1);
    }

    function canClaim(address stex, uint256 idLPWithdrawal) external view returns (bool) {
        IWithdrawalModule withdrawalModule = IWithdrawalModule(ISTEXAMM(stex).withdrawalModule());

        LPWithdrawalRequest memory request = withdrawalModule.getLPWithdrawals(idLPWithdrawal);

        if (request.amountToken1 == 0) {
            return false;
        }

        // Check if there is enough ETH available to fulfill this request
        if (withdrawalModule.amountToken1ClaimableLPWithdrawal() < request.amountToken1) {
            return false;
        }

        // Check if it is the right time to claim (according to queue priority)
        if (
            withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal()
                < request.cumulativeAmountToken1LPWithdrawalCheckpoint + request.amountToken1
        ) {
            return false;
        }

        return true;
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _getSharesForDeposit(address stex, uint256 amount, uint256 reserve0Pool, uint256 reserve1Pool)
        private
        view
        returns (uint256)
    {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        uint256 totalSupplyCache = ERC20(stex).totalSupply();
        if (totalSupplyCache == 0) {
            return amount - MINIMUM_LIQUIDITY;
        }
        IWithdrawalModule withdrawalModule = IWithdrawalModule(stexInterface.withdrawalModule());
        // Account for token0 in pool (liquid) and pending unstaking (locked)
        uint256 reserve0Total = reserve0Pool + withdrawalModule.amountToken0PendingUnstaking();
        // Account for token1 pending withdrawal to LPs (locked)
        uint256 reserve1PendingWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
        // shares calculated in terms of token1
        uint256 shares = Math.mulDiv(
            amount,
            totalSupplyCache,
            reserve1Pool + withdrawalModule.amountToken1LendingPool() + withdrawalModule.convertToToken1(reserve0Total)
                - reserve1PendingWithdrawal
        );

        return shares;
    }
}
