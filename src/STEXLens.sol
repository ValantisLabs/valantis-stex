// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {IstHYPE} from "./interfaces/IStHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

/**
 * @notice Helper contract to simulate execution results from STEX AMM.
 */
contract STEXLens {
    using SafeCast for int256;

    /**
     *
     *  CUSTOM INTERNAL STRUCTS
     *
     */
    struct WithdrawCache {
        uint256 reserve1Pool;
        uint256 preUnstakingShares;
        uint256 pendingUnstakingShares;
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
    function getSharesForDeposit(address _stex, uint256 _amount) external view returns (uint256) {
        if (_amount == 0) return 0;

        ISTEXAMM stexInterface = ISTEXAMM(_stex);

        uint256 totalSupplyCache = ERC20(_stex).totalSupply();
        if (totalSupplyCache == 0) {
            return _amount - MINIMUM_LIQUIDITY;
        } else {
            address poolAddress = stexInterface.pool();
            (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(poolAddress).getReserves();

            address withdrawalModuleAddress = stexInterface.withdrawalModule();
            IWithdrawalModule withdrawalModule = IWithdrawalModule(withdrawalModuleAddress);

            int256 amount0Correction = withdrawalModule.amount0Correction();
            // Account for token0 in pool (liquid) and pending unstaking (locked)
            uint256 reserve0Total;
            if (amount0Correction >= 0) {
                reserve0Total = reserve0Pool + amount0Correction.toUint256();
            } else {
                uint256 amount0CorrectionAbs = (-amount0Correction).toUint256();
                reserve0Total = reserve0Pool > amount0CorrectionAbs ? reserve0Pool - amount0CorrectionAbs : 0;
            }

            // shares calculated in terms of token1
            return Math.mulDiv(
                _amount,
                totalSupplyCache,
                reserve1Pool + withdrawalModule.amountToken1LendingPool()
                    + withdrawalModule.convertToToken1(reserve0Total)
            );
        }
    }

    function getAmountsForWithdraw(address _stex, uint256 _shares, bool _isInstantWithdrawal)
        external
        view
        returns (uint256, uint256)
    {
        if (_shares == 0) return (0, 0);

        ISTEXAMM stexInterface = ISTEXAMM(_stex);
        uint256 totalSupplyCache = ERC20(_stex).totalSupply();
        if (totalSupplyCache == 0) {
            return (0, 0);
        }

        uint256 amount0;
        uint256 amount1;
        address withdrawalModuleAddress = stexInterface.withdrawalModule();
        IWithdrawalModule withdrawalModule = IWithdrawalModule(withdrawalModuleAddress);

        address pool = stexInterface.pool();

        WithdrawCache memory cache;

        (, cache.reserve1Pool) = ISovereignPool(pool).getReserves();

        {
            // token0 shares due to recipient which are currently in pool (liquid),
            // but are yet to be unstaked into token1
            cache.preUnstakingShares =
                Math.mulDiv(_claimablePreUnstakingToken0Shares(withdrawalModule, pool), _shares, totalSupplyCache);
            // token0 shares due to recipient which is currently pending unstaking into token1
            cache.pendingUnstakingShares =
                Math.mulDiv(_claimablePendingUnstakingToken0Shares(withdrawalModule), _shares, totalSupplyCache);

            // token1 amount which is due to recipient and is currently deposited into lending protocol
            // It is assumed that this will be available for instant withdrawal
            cache.amount1LendingPool =
                Math.mulDiv(withdrawalModule.amountToken1LendingPool(), _shares, totalSupplyCache);

            // Total amount of token1 due to recipient now
            amount1 = cache.amount1LendingPool + Math.mulDiv(cache.reserve1Pool, _shares, totalSupplyCache);
            // Total amount of token0 which will be unstaked into token1,
            // and then claimable by recipient once unstaking has been processed
            amount0 = withdrawalModule.token0SharesToBalance(cache.preUnstakingShares + cache.pendingUnstakingShares);
        }

        // This is equivalent to an instant swap into token1 (with an extra fee in token1),
        // and withdraw the total amount in token1
        if (_isInstantWithdrawal) {
            uint256 amount1SwapEquivalent = stexInterface.getAmountOut(stexInterface.token0(), amount0);
            // Apply manager fee on instant withdrawals in token1
            cache.instantWithdrawalFee1 = (amount1SwapEquivalent * ISovereignPool(pool).poolManagerFeeBips()) / BIPS;
            amount1 += (amount1SwapEquivalent - cache.instantWithdrawalFee1);

            amount0 = 0;
        }

        return (amount0, amount1);
    }

    function canClaim(address _stex, uint256 _idLPWithdrawal) external view returns (bool) {
        address withdrawalModuleAddress = ISTEXAMM(_stex).withdrawalModule();
        IWithdrawalModule withdrawalModule = IWithdrawalModule(withdrawalModuleAddress);

        LPWithdrawalRequest memory request = withdrawalModule.getLPWithdrawals(_idLPWithdrawal);

        // Request either does not exist or has already been claimed
        if (request.shares == 0) {
            return false;
        }

        // Check if the unstaking epoch id has already been processed
        if (withdrawalModule.epochExchangeRate(request.epochId) == 0) {
            return false;
        }

        return true;
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _claimablePreUnstakingToken0Shares(IWithdrawalModule withdrawalModule, address pool)
        private
        view
        returns (uint256)
    {
        uint256 sharesPreUnstakingPool = withdrawalModule.token0SharesOf(pool);
        uint256 sharesPreUnstakingLPWithdrawals = withdrawalModule.amountToken0SharesPreUnstakingLPWithdrawal();

        // Claimable amount of token0 shares prior to unstaking
        // are calculated as the excess positive amount of:
        // token0 shares which exist as pool reserves (liquid) - token0 shares already claimed by previous LP withdrawals
        // Those will be unstaked back into token1 through withdrawal module on the next unstaking epoch
        return sharesPreUnstakingPool > sharesPreUnstakingLPWithdrawals
            ? sharesPreUnstakingPool - sharesPreUnstakingLPWithdrawals
            : 0;
    }

    function _claimablePendingUnstakingToken0Shares(IWithdrawalModule withdrawalModule)
        private
        view
        returns (uint256)
    {
        uint256 sharesPendingUnstaking = withdrawalModule.amountToken0SharesPendingUnstaking();
        uint256 sharesPendingUnstakingLPWithdrawals = withdrawalModule.amountToken0SharesPendingUnstakingLPWithdrawal();

        // Claimable amount of token0 shares which are currently being unstaked through the withdrawal module
        // are calculated as the excess positive amount of:
        // token0 shares which have been burnt and are pending unstaking - token0 shares already claimed by previous LP withdrawals
        return sharesPendingUnstaking > sharesPendingUnstakingLPWithdrawals
            ? sharesPendingUnstaking - sharesPendingUnstakingLPWithdrawals
            : 0;
    }
}
