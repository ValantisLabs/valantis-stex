// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

abstract contract Fee is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error Fee__onlyPool();
    error Fee__getFee_ReserveToken1TargetIsZero();
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
        uint32 feeMinPips;
        uint32 feeMaxPips;
    }

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 internal constant PIPS = 1_000_000;

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
    function getSwapFee() public view returns (uint256 feePips) {
        (, uint256 reserve1) = _pool.getReserves();

        FeeParams memory feeParamsCache = feeParams;

        if (reserve1 > feeParamsCache.reserve1Target) {
            feePips = uint256(feeParamsCache.feeMinPips);
        } else {
            if (feeParamsCache.reserve1Target == 0) {
                revert Fee__getFee_ReserveToken1TargetIsZero();
            }

            feePips =
                uint256(feeParamsCache.feeMaxPips) -
                (uint256(
                    (feeParamsCache.feeMaxPips - feeParamsCache.feeMinPips)
                ) * reserve1) /
                uint256(feeParamsCache.reserve1Target);
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function setSwapFeeParams(
        uint128 _reserve1Target,
        uint32 _feeMinPips,
        uint32 _feeMaxPips
    ) external onlyOwner {
        if (_feeMinPips >= PIPS) revert Fee_setSwapFeeParams_invalidFeeMin();
        if (_feeMaxPips >= PIPS) revert Fee_setSwapFeeParams_invalidFeeMax();

        if (_feeMinPips > _feeMaxPips) {
            revert Fee_setSwapFeeParams_inconsistentFeeParams();
        }

        feeParams = FeeParams({
            reserve1Target: _reserve1Target,
            feeMinPips: _feeMinPips,
            feeMaxPips: _feeMaxPips
        });
    }
}
