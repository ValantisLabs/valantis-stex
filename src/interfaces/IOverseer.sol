// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IOverseer {
    function burn(address to, uint256 amount) external returns (uint256);
    function maxRedeemable() external view returns (uint256);
    function burnAndRedeemIfPossible(address to, uint256 amount, string memory communityCode)
        external
        returns (uint256 burnId);
    function redeem(uint256 burnId) external returns (uint256);
}
