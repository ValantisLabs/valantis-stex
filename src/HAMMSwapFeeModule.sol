// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {FeeParams} from "./structs/HAMMSwapFeeModuleStructs.sol";
import {IHAMMSwapFeeModule} from "./interfaces/IHAMMSwapFeeModule.sol";

contract HAMMSwapFeeModule is IHAMMSwapFeeModule, Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error HAMMSwapFeeModule__ZeroAddress();
    error HAMMSwapFeeModule__getSwapFeeInBips_ReserveToken1TargetIsZero();
    error HAMMSwapFeeModule__setSwapFeeParams_inconsistentFeeParams();
    error HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMin();
    error HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMax();
    error HAMMSwapFeeModule__setPool_alreadySet();

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
    FeeParams public feeParams;

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function getSwapFeeInBips(
        address _tokenIn,
        address, /*_tokenOut*/
        uint256, /*_amountIn*/
        address, /*_user*/
        bytes memory /*_swapFeeModuleContext*/
    ) external view override returns (SwapFeeModuleData memory swapFeeModuleData) {
        ISovereignPool poolInterface = ISovereignPool(pool);
        // Fee is only applied on token0 -> token1 swaps
        if (_tokenIn == poolInterface.token0()) {
            (, uint256 reserve1) = poolInterface.getReserves();

            FeeParams memory feeParamsCache = feeParams;
            uint256 feeInBips;
            if (reserve1 > feeParamsCache.reserve1Target) {
                feeInBips = uint256(feeParamsCache.feeMinBips);
            } else {
                if (feeParamsCache.reserve1Target == 0) {
                    revert HAMMSwapFeeModule__getSwapFeeInBips_ReserveToken1TargetIsZero();
                }

                feeInBips = uint256(feeParamsCache.feeMaxBips)
                    - (uint256((feeParamsCache.feeMaxBips - feeParamsCache.feeMinBips)) * reserve1)
                        / uint256(feeParamsCache.reserve1Target);
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
    function setPool(address _pool) external onlyOwner {
        if (_pool == address(0)) revert HAMMSwapFeeModule__ZeroAddress();
        // Pool can only be set once
        if (pool != address(0)) revert HAMMSwapFeeModule__setPool_alreadySet();
        pool = _pool;
    }

    /**
     * @notice Update AMM's dynamic swap fee parameters.
     * @dev Only callable by `owner`.
     * @param _reserve1Target Target token1 reserves.
     * @param _feeMinBips Lower-bound for the dynamic swap fee.
     * @param _feeMaxBips Upper-bound for the dynamic swap fee.
     */
    function setSwapFeeParams(uint128 _reserve1Target, uint32 _feeMinBips, uint32 _feeMaxBips)
        external
        override
        onlyOwner
    {
        // Fees must be lower than 50% (5_000 bips)
        if (_feeMinBips >= BIPS / 2) {
            revert HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMin();
        }
        if (_feeMaxBips >= BIPS / 2) {
            revert HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMax();
        }

        if (_feeMinBips > _feeMaxBips) {
            revert HAMMSwapFeeModule__setSwapFeeParams_inconsistentFeeParams();
        }

        feeParams = FeeParams({reserve1Target: _reserve1Target, feeMinBips: _feeMinBips, feeMaxBips: _feeMaxBips});
    }
}
