// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

struct LPWithdrawalRequest {
    address recipient;
    uint96 shares;
    uint160 epochId; // Epoch in which this withdrawal request was created
}

struct LendingModuleProposal {
    address lendingModule;
    uint256 startTimestamp;
}
