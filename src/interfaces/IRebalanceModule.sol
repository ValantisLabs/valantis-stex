// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IRebalanceModule {
    function rebalance(uint256 amountToken1Min, bytes calldata _data) external returns (bytes4);
}
