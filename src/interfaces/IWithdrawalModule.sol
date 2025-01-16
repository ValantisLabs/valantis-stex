// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IWithdrawalModule {
    function amountPendingUnstaking() external view returns (uint256);

    function unstakeToken0Reserves() external;

    function burnAfterWithdraw(uint256 _amountToken0, address _recipient) external;
}
