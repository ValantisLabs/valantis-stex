// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IWithdrawalModule {
    function overseer() external view returns (address);

    function initializer() external view returns (address);

    function hamm() external view returns (address);

    function amountPendingUnstaking() external view returns (uint256);

    function unstakeToken0Reserves() external;

    function burnAfterWithdraw(uint256 _amountToken0, address _recipient) external;
}
