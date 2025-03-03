// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {IstHYPE} from "./interfaces/IStHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

contract STEXLens {
    struct WithdrawCache {
        uint256 reserve0Pool;
        uint256 reserve1Pool;
        uint256 poolShares;
        uint256 pendingUnstakingShares;
        uint256 amount1LendingPool;
        uint256 instantWithdrawalFee1;
        uint256 amount1Remaining;
    }

    uint256 private constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant BIPS = 1e4;

    function getSharesForDeposit(address stex, uint256 amount) external view returns (uint256) {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        uint256 totalSupplyCache = ERC20(stex).totalSupply();
        if (totalSupplyCache == 0) {
            return amount - MINIMUM_LIQUIDITY;
        }
        IWithdrawalModule withdrawalModule = IWithdrawalModule(stexInterface.withdrawalModule());
        (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(stexInterface.pool()).getReserves();

        int256 amount0Correction = withdrawalModule.amount0Correction();
        // Account for token0 in pool (liquid) and pending unstaking (locked)
        uint256 reserve0Total;
        if (amount0Correction >= 0) {
            reserve0Total = reserve0Pool + uint256(amount0Correction);
        } else {
            reserve0Total = reserve0Pool - uint256(-amount0Correction);
        }

        // shares calculated in terms of token1
        uint256 shares = Math.mulDiv(
            amount,
            totalSupplyCache,
            reserve1Pool + withdrawalModule.amountToken1LendingPool() + withdrawalModule.convertToToken1(reserve0Total)
        );

        return shares;
    }

    function getSharesForWithdraw(address stex, uint256 shares, bool isInstantWithdrawal)
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

        {
            // Calculate pool shares and pending unstaking shares
            cache.poolShares = Math.mulDiv(
                IstHYPE(stexInterface.token0()).sharesOf(stexInterface.pool())
                    - withdrawalModule.amountToken0SharesPendingLPWithdrawal(),
                shares,
                totalSupplyCache
            );
            cache.pendingUnstakingShares = Math.mulDiv(
                withdrawalModule.amountToken0SharesPendingUnstaking()
                    - withdrawalModule.amountToken0SharesUnstakingLPWithdrawal(),
                shares,
                totalSupplyCache
            );

            cache.amount1LendingPool = Math.mulDiv(withdrawalModule.amountToken1LendingPool(), shares, totalSupplyCache);
            // token1 amount calculated as pro-rata share of token1 reserves in the pool (liquid)
            // plus pro-rata share of token1 reserves earning yield in lending pool (liquid)
            amount1 = cache.amount1LendingPool + Math.mulDiv(cache.reserve1Pool, shares, totalSupplyCache);
            amount0 = IstHYPE(stexInterface.token0()).sharesToBalance(cache.poolShares + cache.pendingUnstakingShares);
        }

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

        if (request.shares == 0) {
            return false;
        }

        // Check if the epoch exchange rate exists (request hasn't been claimed yet)
        if (withdrawalModule.epochExchangeRate(request.epochId) == 0) {
            return false;
        }

        return true;
    }
}
