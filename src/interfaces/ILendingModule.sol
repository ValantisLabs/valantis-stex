// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ILendingModule {
    function assetBalance() external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount, address recipient) external;
}
