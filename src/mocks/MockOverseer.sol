// SPDX-License-Identifier: BUSL-1.1
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

    function burn(address to, uint256 amount) external override returns (uint256) {
        require(to != address(0), "invalid address");
        require(amount > 0, "invalid amount");

        burnsById[burnId] = Burn({to: to, amount: amount});

        burnId++;

        return burnId;
    }

    function settleBurn(uint256 id) external {
        Burn memory burnRequest = burnsById[id];

        if (burnRequest.amount == 0) return;

        delete burnsById[id];

        (bool success,) = burnRequest.to.call{value: burnRequest.amount}("");
        require(success, "failed to send ETH");
    }
}
