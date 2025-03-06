// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IOverseer} from "../interfaces/IOverseer.sol";

contract MockOverseer is IOverseer {
    struct Burn {
        address to;
        uint256 amount;
        bool completed;
    }

    bool public isCompromised;

    uint256 public burnId;

    mapping(uint256 => Burn) public burnsById;

    receive() external payable {}

    function setIsCompromised(bool value) public {
        isCompromised = value;
    }

    function redeemable(uint256 _burnId) external view returns (bool) {
        Burn memory burnRequest = burnsById[_burnId];
        return !burnRequest.completed && burnRequest.amount <= address(this).balance;
    }

    function burnAndRedeemIfPossible(address to, uint256 amount, string memory /*_communityCode*/ )
        external
        override
        returns (uint256)
    {
        require(to != address(0), "invalid address");
        require(amount > 0, "invalid amount");

        burnsById[burnId] = Burn({to: to, amount: amount, completed: false});

        burnId++;

        return burnId - 1;
    }

    function redeem(uint256 _burnId) external override {
        // Simulates a faulty implementation
        if (isCompromised) return;

        Burn storage burnRequest = burnsById[_burnId];

        if (burnRequest.completed) return;

        burnRequest.completed = true;

        (bool success,) = burnRequest.to.call{value: burnRequest.amount}("");
        require(success, "failed to send ETH");
    }
}
