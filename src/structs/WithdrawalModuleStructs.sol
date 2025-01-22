// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

struct LPWithdrawalRequest {
    address recipient;
    uint96 amountToken1;
    uint256 cumulativeAmountToken1ClaimableLPWithdrawalCheckpoint;
}
