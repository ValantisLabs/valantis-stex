// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IWithdrawalModule {
    function overseer() external view returns (address);

    function lendingPool() external view returns (address);

    function stex() external view returns (address);

    function amountToken0PendingUnstaking() external view returns (uint256);

    function amountToken1LendingPool() external view returns (uint256);

    function amountToken1PendingLPWithdrawal() external view returns (uint256);

    function convertToToken0(uint256 _amountToken1) external view returns (uint256);

    function convertToToken1(uint256 _amountToken0) external view returns (uint256);

    function unstakeToken0Reserves() external;

    function burnToken0AfterWithdraw(uint256 _amountToken0, address _recipient) external;

    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient) external;
}
