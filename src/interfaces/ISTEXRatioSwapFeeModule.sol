// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISwapFeeModuleMinimal} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

interface ISTEXRatioSwapFeeModule is ISwapFeeModuleMinimal {
    event PoolSet(address pool);

    event SwapFeeParamsSet(
        uint32 minThresholdRatioBips, uint32 maxThresholdRatioBips, uint32 feeMinBips, uint32 feeMaxBips
    );

    function setSwapFeeParams(
        uint32 _minThresholdRatioBips,
        uint32 _maxThresholdRatioBips,
        uint32 _feeMinBips,
        uint32 _feeMaxBips
    ) external;
}
