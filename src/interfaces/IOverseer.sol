// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IOverseer {
    function burns(uint256 id) external view returns (uint88, address, bool, uint256);

    function burnAndRedeemIfPossible(address to, uint256 amount, string memory communityCode)
        external
        returns (uint256 burnId);

    function redeem(uint256 burnId) external;

    function redeemable(uint256 burnId) external view returns (bool);
}
