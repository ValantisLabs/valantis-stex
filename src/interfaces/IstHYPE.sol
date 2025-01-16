// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IstHYPE {
    function assetsToShares(uint256 assets) external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);
}
