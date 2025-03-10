// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {FeeParams} from "./structs/STEXRatioSwapFeeModuleStructs.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {ISTEXRatioSwapFeeModule} from "./interfaces/ISTEXRatioSwapFeeModule.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";

/**
 * @title Stake Exchange: Reserves Ratio based Swap Fee Module.
 */
contract STEXRatioSwapFeeModule is ISTEXRatioSwapFeeModule, Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error STEXRatioSwapFeeModule__ZeroAddress();
    error STEXRatioSwapFeeModule__getSwapFeeInBips_ZeroReserveToken1();
    error STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentFeeParams();
    error STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMin();
    error STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMax();
    error STEXRatioSwapFeeModule__setSwapFeeParams_invalidMinThresholdRatio();
    error STEXRatioSwapFeeModule__setSwapFeeParams_invalidMaxThresholdRatio();
    error STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentThresholdRatioParams();
    error STEXRatioSwapFeeModule__setPool_alreadySet();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @notice Address of Valantis Sovereign Pool.
     */
    address public pool;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @notice Dynamic swap fee parameters.
     */
    FeeParams public feeParams;

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function getSwapFeeInBips(
        address _tokenIn,
        address, /*_tokenOut*/
        uint256 _amountIn,
        address, /*_user*/
        bytes memory /*_swapFeeModuleContext*/
    ) external view override returns (SwapFeeModuleData memory swapFeeModuleData) {
        ISovereignPool poolInterface = ISovereignPool(pool);
        ISTEXAMM stexInterface = ISTEXAMM(poolInterface.alm());
        // Fee is only applied on token0 -> token1 swaps
        if (_tokenIn == poolInterface.token0()) {
            (uint256 reserve0, uint256 reserve1) = poolInterface.getReserves();
            IWithdrawalModule withdrawalModuleInterface = IWithdrawalModule(stexInterface.withdrawalModule());

            uint256 amount0PendingUnstaking = withdrawalModuleInterface.amountToken0PendingUnstaking();
            uint256 amountToken0PendingLPWithdrawal =
                withdrawalModuleInterface.convertToToken0(withdrawalModuleInterface.amountToken1PendingLPWithdrawal());

            uint256 amount0Total = reserve0 + amount0PendingUnstaking + _amountIn - amountToken0PendingLPWithdrawal;

            FeeParams memory feeParamsCache = feeParams;
            uint256 feeInBips;

            uint256 reserve1Total = reserve1 + withdrawalModuleInterface.amountToken1LendingPool();

            if (reserve1Total == 0) {
                revert STEXRatioSwapFeeModule__getSwapFeeInBips_ZeroReserveToken1();
            }

            uint256 ratioBips = (amount0Total * BIPS) / reserve1Total;

            if (ratioBips > feeParamsCache.maxThresholdRatioBips) {
                feeInBips = feeParamsCache.feeMaxBips;
            } else if (ratioBips < feeParamsCache.minThresholdRatioBips) {
                feeInBips = feeParamsCache.feeMinBips;
            } else {
                uint256 numerator = ratioBips - feeParamsCache.minThresholdRatioBips;
                uint256 denominator = feeParamsCache.maxThresholdRatioBips - feeParamsCache.minThresholdRatioBips;

                feeInBips = feeParamsCache.feeMinBips
                    + ((feeParamsCache.feeMaxBips - feeParamsCache.feeMinBips) * numerator) / denominator;
            }

            // Swap fee in `SovereignPool::swap` is applied as:
            // amountIn * BIPS / (BIPS + swapFeeModuleData.feeInBips),
            // but our parametrization assumes the form: amountIn * (BIPS - feeInBips) / BIPS
            // Hence we need to equate both and solve for `swapFeeModuleData.feeInBips`,
            // with the constraint that feeInBips <= 5_000
            swapFeeModuleData.feeInBips = (BIPS * BIPS) / (BIPS - feeInBips) - BIPS;
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Sets address of Valantis Sovereign Pool.
     * @param _pool Address of Valantis Sovereign Pool to set.
     * @dev Callable by `owner` only once.
     */
    function setPool(address _pool) external onlyOwner {
        if (_pool == address(0)) revert STEXRatioSwapFeeModule__ZeroAddress();
        // Pool can only be set once
        if (pool != address(0)) {
            revert STEXRatioSwapFeeModule__setPool_alreadySet();
        }
        pool = _pool;

        emit PoolSet(_pool);
    }

    /**
     * @notice Update AMM's dynamic swap fee parameters.
     * @dev Only callable by `owner`.
     * @param _minThresholdRatioBips Threshold value below which `_feeMinBips` will be applied.
     * @param _maxThresholdRatioBips Threshold value above which `_feeMaxBips` will be applied.
     * @param _feeMinBips Lower-bound for the dynamic swap fee.
     * @param _feeMaxBips Upper-bound for the dynamic swap fee.
     */
    function setSwapFeeParams(
        uint32 _minThresholdRatioBips,
        uint32 _maxThresholdRatioBips,
        uint32 _feeMinBips,
        uint32 _feeMaxBips
    ) external override onlyOwner {
        // Reserve ratio threshold params must be in BIPS
        if (_minThresholdRatioBips >= BIPS) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_invalidMinThresholdRatio();
        }
        if (_maxThresholdRatioBips > BIPS) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_invalidMaxThresholdRatio();
        }
        if (_minThresholdRatioBips >= _maxThresholdRatioBips) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentThresholdRatioParams();
        }

        // Fees must be lower than 50% (5_000 bips)
        if (_feeMinBips >= BIPS / 2) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMin();
        }
        if (_feeMaxBips >= BIPS / 2) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMax();
        }

        if (_feeMinBips > _feeMaxBips) {
            revert STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentFeeParams();
        }

        feeParams = FeeParams({
            minThresholdRatioBips: _minThresholdRatioBips,
            maxThresholdRatioBips: _maxThresholdRatioBips,
            feeMinBips: _feeMinBips,
            feeMaxBips: _feeMaxBips
        });

        emit SwapFeeParamsSet(_minThresholdRatioBips, _maxThresholdRatioBips, _feeMinBips, _feeMaxBips);
    }
}
