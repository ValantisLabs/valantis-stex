// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IOverseer {
    function burnAndRedeemIfPossible(address to, uint256 amount, string memory communityCode)
        external
        returns (uint256 burnId);

    function redeem(uint256 burnId) external;

    function redeemable(uint256 burnId) external view returns (bool);

    function getBurnIds(address account) external view returns (uint256[] memory);
}
