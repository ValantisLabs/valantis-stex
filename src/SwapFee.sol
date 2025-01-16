// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ISwapFeeModuleMinimal, SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

abstract contract SwapFee is ISwapFeeModuleMinimal, Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error Fee__onlyPool();
    error Fee__getSwapFeeInBips_InvalidSwapDirection();
    error Fee__getSwapFeeInBips_ReserveToken1TargetIsZero();
    error Fee_setSwapFeeParams_invalidFeeMin();
    error Fee_setSwapFeeParams_invalidFeeMax();
    error Fee_setSwapFeeParams_inconsistentFeeParams();

    /**
     *
     *  STRUCTS
     *
     */
    struct FeeParams {
        uint128 reserve1Target;
        uint32 feeMinBips;
        uint32 feeMaxBips;
    }

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;

    /**
     *
     *  IMMUTABLES
     *
     */
    ISovereignPool internal immutable _pool;

    /**
     *
     *  STORAGE
     *
     */
    FeeParams public feeParams;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address pool_, address owner_) Ownable(owner_) {
        _pool = ISovereignPool(pool_);
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyPool() {
        if (msg.sender != address(_pool)) {
            revert Fee__onlyPool();
        }
        _;
    }

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
        if (_tokenIn != _pool.token0()) {
            revert Fee__getSwapFeeInBips_InvalidSwapDirection();
        }

        (, uint256 reserve1) = _pool.getReserves();

        FeeParams memory feeParamsCache = feeParams;

        if (reserve1 > feeParamsCache.reserve1Target) {
            swapFeeModuleData.feeInBips = uint256(feeParamsCache.feeMinBips);
        } else {
            if (feeParamsCache.reserve1Target == 0) {
                revert Fee__getSwapFeeInBips_ReserveToken1TargetIsZero();
            }

            swapFeeModuleData.feeInBips = uint256(feeParamsCache.feeMaxBips)
                - (uint256((feeParamsCache.feeMaxBips - feeParamsCache.feeMinBips)) * reserve1)
                    / uint256(feeParamsCache.reserve1Target);
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function setSwapFeeParams(uint128 _reserve1Target, uint32 _feeMinBips, uint32 _feeMaxBips) external onlyOwner {
        if (_feeMinBips >= BIPS) revert Fee_setSwapFeeParams_invalidFeeMin();
        if (_feeMaxBips >= BIPS) revert Fee_setSwapFeeParams_invalidFeeMax();

        if (_feeMinBips > _feeMaxBips) {
            revert Fee_setSwapFeeParams_inconsistentFeeParams();
        }

        feeParams = FeeParams({reserve1Target: _reserve1Target, feeMinBips: _feeMinBips, feeMaxBips: _feeMaxBips});
    }
}
