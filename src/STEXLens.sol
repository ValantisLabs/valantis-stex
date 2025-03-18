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
        uint256 totalSupplyCache = ERC20(stex).totalSupply();
        if (totalSupplyCache == 0) {
            return amount - MINIMUM_LIQUIDITY;
        }
        IWithdrawalModule withdrawalModule = IWithdrawalModule(stexInterface.withdrawalModule());
        (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();
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

        // Account for token1 pending withdrawal to LPs (locked)
        uint256 reserve1PendingWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
        // pro-rata share of token0 reserves in pool (liquid), token0 reserves pending in withdrawal queue (locked)
        // minus LP amount already pending withdrawal
        amount0 = Math.mulDiv(
            cache.reserve0Pool + withdrawalModule.amountToken0PendingUnstaking()
                - withdrawalModule.convertToToken0(reserve1PendingWithdrawal),
            shares,
            totalSupplyCache
        );

        cache.amount1LendingPool = Math.mulDiv(withdrawalModule.amountToken1LendingPool(), shares, totalSupplyCache);
        // token1 amount calculated as pro-rata share of token1 reserves in the pool (liquid)
        // plus pro-rata share of token1 reserves earning yield in lending pool (liquid, assuming lending pool is working correctly)
        amount1 = cache.amount1LendingPool + Math.mulDiv(cache.reserve1Pool, shares, totalSupplyCache);

        if (isInstantWithdrawal) {
            uint256 amount1SwapEquivalent = stexInterface.getAmountOut(stexInterface.token0(), amount0);
            // Apply manager fee on instant withdrawals in token1
            cache.instantWithdrawalFee1 =
                (amount1SwapEquivalent * ISovereignPool(stexInterface.pool()).poolManagerFeeBips()) / BIPS;
            amount1 += (amount1SwapEquivalent - cache.instantWithdrawalFee1);

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
}
