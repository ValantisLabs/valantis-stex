// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

struct SwapFeeModuleProposal {
    address swapFeeModule;
    uint256 startTimestamp;
}

struct WithdrawalModuleProposal {
    address withdrawalModule;
    uint256 startTimestamp;
}
