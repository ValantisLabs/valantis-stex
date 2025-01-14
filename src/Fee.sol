// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

abstract contract Fee {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error Fee__onlyPool();
    error Fee__getFee_ReserveToken1TargetIsZero();

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
    address public immutable pool;

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
    constructor(address _pool) {
        pool = _pool;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyPool() {
        if (msg.sender != pool) {
            revert Fee__onlyPool();
        }
        _;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function getFee() public view returns (uint256 feePips) {
        (, uint256 reserve1) = ISovereignPool(pool).getReserves();

        FeeParams memory feeParamsCache = feeParams;

        if (reserve1 > feeParamsCache.reserve1Target) {
            feePips = uint256(feeParams.feeMinPips);
        } else {
            if (feeParamsCache.reserve1Target == 0) {
                revert Fee__getFee_ReserveToken1TargetIsZero();
            }

            feePips = uint256(feeParamsCache.feeMaxPips)
                - (uint256((feeParamsCache.feeMaxPips - feeParamsCache.feeMinPips)) * reserve1)
                    / uint256(feeParamsCache.reserve1Target);
        }
    }
}
