// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IOverseer {
    function burn(address to, uint256 amount) external returns (uint256);
}
