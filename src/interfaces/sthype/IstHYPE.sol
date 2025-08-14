// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IstHYPE {
    function balanceOf(address who) external view returns (uint256);

    function sharesOf(address who) external view returns (uint256);

    function sharesToBalance(uint256 shares) external view returns (uint256);

    function balanceToShares(uint256 balance) external view returns (uint256);
}
