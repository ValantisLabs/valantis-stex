// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

struct FeeParams {
    uint128 reserve1Target;
    uint32 feeMinBips;
    uint32 feeMaxBips;
}
