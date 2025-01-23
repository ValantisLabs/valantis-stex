// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

struct FeeParams {
    uint32 minThresholdRatioBips;
    uint32 maxThresholdRatioBips;
    uint32 feeMinBips;
    uint32 feeMaxBips;
}
