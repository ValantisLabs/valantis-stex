// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IOverseer} from "../interfaces/IOverseer.sol";

contract MockOverseer is IOverseer {
    struct Burn {
        address to;
        uint256 amount;
    }

    uint256 public burnId;

    mapping(uint256 => Burn) public burnsById;

    receive() external payable {}

    function redeemable(uint256 _burnId) external view returns (bool) {
        uint256 amount = burnsById[_burnId].amount;
        return amount > 0 && amount <= address(this).balance;
    }

    function burnAndRedeemIfPossible(
        address to,
        uint256 amount,
        string memory /*_communityCode*/
    ) external override returns (uint256) {
        require(to != address(0), "invalid address");
        require(amount > 0, "invalid amount");

        burnsById[burnId] = Burn({to: to, amount: amount});

        burnId++;

        return burnId;
    }

    function redeem(uint256 _burnId) external override {
        Burn memory burnRequest = burnsById[_burnId];

        if (burnRequest.amount == 0) return;

        delete burnsById[_burnId];

        (bool success, ) = burnRequest.to.call{value: burnRequest.amount}("");
        require(success, "failed to send ETH");
    }
}
