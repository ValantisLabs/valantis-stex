// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface IWithdrawalModule {
    function burn(uint256 amountToken0) external;
}
