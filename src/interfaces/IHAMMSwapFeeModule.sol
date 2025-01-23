// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISwapFeeModuleMinimal} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

interface IHAMMSwapFeeModule is ISwapFeeModuleMinimal {
    function setSwapFeeParams(uint128 _reserve1Target, uint32 _feeMinBips, uint32 _feeMaxBips) external;
}
