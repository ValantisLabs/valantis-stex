// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISwapFeeModuleMinimal} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

interface IStepwiseFeeModule is ISwapFeeModuleMinimal {
    event PoolSet(address pool);

    event FeeParamsSetToken0(uint256 maxThresholdToken1, uint256 minThresholdToken1, uint256 numStepsToken1);
}
