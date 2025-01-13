// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignPool} from "lib/valantis-core/src/pools/interfaces/ISovereignPool.sol";

abstract contract Fee {
    error Fee__onlyPool();
    error Fee__getFee_ReserveToken1TargetIsZero();

    struct FeeParams {
        uint128 reserve1Target;
        uint32 feeMinPips;
        uint32 feeMaxPips;
    }

    uint256 internal constant PIPS = 1_000_000;

    address public immutable pool;

    FeeParams public feeParams;

    constructor(address _pool) {
        pool = _pool;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert Fee__onlyPool();
        }
        _;
    }

    function getFee() public view returns (uint256 feePips) {
        (, uint256 reserve1) = ISovereignPool(pool).getReserves();

        FeeParams memory feeParamsCache = feeParams;

        if (reserve1 > feeParamsCache.reserve1Target) {
            feePips = uint256(feeParams.feeMinPips);
        } else {
            if (feeParamsCache.reserve1Target == 0)
                revert Fee__getFee_ReserveToken1TargetIsZero();

            feePips =
                uint256(feeParamsCache.feeMaxPips) -
                (uint256(
                    (feeParamsCache.feeMaxPips - feeParamsCache.feeMinPips)
                ) * reserve1) /
                uint256(feeParamsCache.reserve1Target);
        }
    }
}
