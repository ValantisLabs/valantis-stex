// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {ISTEXAMM} from "../interfaces/ISTEXAMM.sol";

import {IStepwiseFeeModule} from "../interfaces/IStepwiseFeeModule.sol";

contract StepwiseFeeModule is IStepwiseFeeModule, Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error StepwiseFeeModule__ZeroAddress();
    error StepwiseFeeModule__getSwapFeeInBips_InvalidMinToken1Threshold();
    error StepwiseFeeModule__getSwapFeeInBips_InvalidMaxToken1Threshold();
    error StepwiseFeeModule__getSwapFeeInBips_InvalidToken1Threshold();
    error StepwiseFeeModule__setPool_AlreadySet();
    error StepwiseFeeModule__setFeeParamsToken0__FeeTooHigh();
    error StepwiseFeeModule__setFeeParamsToken0__FeeTooLow();
    error StepwiseFeeModule__setFeeParamsToken0__FeeStepsNotMonotonicallyNonDecreasing();
    error StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdZero();
    error StepwiseFeeModule__setFeeParamsToken0__MaxToken1ThresholdZero();
    error StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdAboveMaxToken1Threshold();
    error StepwiseFeeModule__setFeeParamsToken0__ZeroSteps();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;

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
     * @notice Supply of token1 where maximum fee is charged.
     */
    uint256 public minThresholdToken1;

    /**
     * @notice Supply of token1 where minimum fee is charged.
     */
    uint256 public maxThresholdToken1;

    /**
     * @notice Number of steps in the Stepwise Fee curve.
     */
    uint256 public numStepsToken0FeeCurve;

    /**
     * @notice Address of Valantis Sovereign Pool.
     */
    address public pool;

    /**
     * @notice Stepwise Fee curve parameters.
     */
    uint32[] private _feeStepwiseInBips;

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function getToken0FeeInBips() external view returns (uint32[] memory) {
        return _feeStepwiseInBips;
    }

    function getSwapFeeInBips(
        address _tokenIn,
        address, /*_tokenOut*/
        uint256 _amountIn,
        address, /*_user*/
        bytes memory /*_swapFeeModuleContext*/
    ) external view override returns (SwapFeeModuleData memory swapFeeModuleData) {
        ISovereignPool poolInterface = ISovereignPool(pool);
        // Fee is only applied on token0 -> token1 swaps
        if (_tokenIn == poolInterface.token0()) {
            uint256 minThresholdToken1Cache = minThresholdToken1;
            uint256 maxThresholdToken1Cache = maxThresholdToken1;
            uint256 numStepsToken0FeeCurveCache = numStepsToken0FeeCurve;

            if (minThresholdToken1Cache == 0) {
                revert StepwiseFeeModule__getSwapFeeInBips_InvalidMinToken1Threshold();
            }
            if (maxThresholdToken1Cache == 0) {
                revert StepwiseFeeModule__getSwapFeeInBips_InvalidMaxToken1Threshold();
            }

            if (maxThresholdToken1Cache <= minThresholdToken1Cache) {
                revert StepwiseFeeModule__getSwapFeeInBips_InvalidToken1Threshold();
            }

            ISTEXAMM stexInterface = ISTEXAMM(poolInterface.alm());
            IWithdrawalModule withdrawalModuleInterface = IWithdrawalModule(stexInterface.withdrawalModule());
            (, uint256 reserve1) = poolInterface.getReserves();
            uint256 reserve1Total = reserve1 + withdrawalModuleInterface.amountToken1LendingPool();
            uint256 expectedToken1Out = withdrawalModuleInterface.convertToToken1(_amountIn);

            uint256 amount1AfterSwap;
            if (reserve1Total > expectedToken1Out) {
                amount1AfterSwap = reserve1Total - expectedToken1Out;
            } else {
                // Do not revert in the swap fee module for low liquidity.
                // amount1AfterSwap is an overestimate, large values should charge the maxFee.
                amount1AfterSwap = 0;
            }

            uint256 feeInBips;

            if (amount1AfterSwap > maxThresholdToken1Cache) {
                // If amount1AfterSwap is greater than the maxThresholdToken1 charge the minimum fee.
                feeInBips = _feeStepwiseInBips[0];
            } else {
                // If amount1AfterSwap is below the threshold, find the corresponding tickNumber
                uint256 tickNumberNumerator = (maxThresholdToken1Cache - amount1AfterSwap) * numStepsToken0FeeCurveCache;
                uint256 tickNumberDenominator = (maxThresholdToken1Cache - minThresholdToken1Cache);
                uint256 tickNumber = tickNumberNumerator / tickNumberDenominator;
                if (tickNumber >= numStepsToken0FeeCurveCache) {
                    feeInBips = _feeStepwiseInBips[numStepsToken0FeeCurveCache - 1];
                } else {
                    feeInBips = _feeStepwiseInBips[tickNumber];
                }
            }

            // Swap fee in `SovereignPool::swap` is applied as:
            // amountIn * BIPS / (BIPS + swapFeeModuleData.feeInBips),
            // but our parametrization assumes the form: amountIn * (BIPS - feeInBips) / BIPS
            // Hence we need to equate both and solve for `swapFeeModuleData.feeInBips`,
            // with the constraint that feeInBips <= 5_000
            swapFeeModuleData.feeInBips = (BIPS * feeInBips) / (BIPS - feeInBips);
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
        if (_pool == address(0)) revert StepwiseFeeModule__ZeroAddress();
        // Pool can only be set once
        if (pool != address(0)) {
            revert StepwiseFeeModule__setPool_AlreadySet();
        }
        pool = _pool;

        emit PoolSet(_pool);
    }

    /**
     * @notice Update AMM's dynamic swap fee parameters for token0->token1 swaps.
     * @dev Only callable by `owner`.
     * @param _minThresholdToken1 Threshold value of token1 reserves below which
     *        the last fee in `feeStepsInBips` will be applied.
     * @param _maxThresholdToken1 Threshold value of token1 reserves above which
     *        the first fee in `feeStepsInBips` will be applied.
     * @param _feeStepsInBips Array of fee steps in bips. The fee will be linearly
     *        interpolated as a function of the token1 reserves below `maxToken1Threshold`.
     *         Items moving between first and last indicies must be strictly increasing in value.
     */
    function setFeeParamsToken0(
        uint256 _minThresholdToken1,
        uint256 _maxThresholdToken1,
        uint32[] calldata _feeStepsInBips
    ) external onlyOwner {
        if (_feeStepsInBips.length == 0) {
            revert StepwiseFeeModule__setFeeParamsToken0__ZeroSteps();
        }

        if (_minThresholdToken1 == 0) {
            revert StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdZero();
        }

        if (_maxThresholdToken1 == 0) {
            revert StepwiseFeeModule__setFeeParamsToken0__MaxToken1ThresholdZero();
        }

        if (_minThresholdToken1 >= _maxThresholdToken1) {
            revert StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdAboveMaxToken1Threshold();
        }

        for (uint32 i = 0; i < _feeStepsInBips.length; i++) {
            if (_feeStepsInBips[i] >= BIPS / 2) {
                revert StepwiseFeeModule__setFeeParamsToken0__FeeTooHigh();
            }

            if (_feeStepsInBips[i] == 0) {
                revert StepwiseFeeModule__setFeeParamsToken0__FeeTooLow();
            }

            if (i > 0 && _feeStepsInBips[i] < _feeStepsInBips[i - 1]) {
                revert StepwiseFeeModule__setFeeParamsToken0__FeeStepsNotMonotonicallyNonDecreasing();
            }
        }

        // Clear current array's elements in storage
        delete _feeStepwiseInBips;

        // Set new params in storage

        minThresholdToken1 = _minThresholdToken1;
        maxThresholdToken1 = _maxThresholdToken1;
        _feeStepwiseInBips = _feeStepsInBips;
        numStepsToken0FeeCurve = _feeStepsInBips.length;

        emit FeeParamsSetToken0(_minThresholdToken1, _maxThresholdToken1, _feeStepsInBips.length);
    }
}
