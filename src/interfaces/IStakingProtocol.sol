// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IStakingProtocol {
    function burn(address to, uint256 amount) external;
}
