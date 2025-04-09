// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IOverseer} from "../interfaces/IOverseer.sol";

import {MockStHype} from "./MockStHype.sol";

contract MockOverseer is IOverseer {
    struct Burn {
        address to;
        uint256 amount;
    }

    uint256 public burnId;

    mapping(uint256 => Burn) public burnsById;

    MockStHype public mockStHype;

    constructor(address _mockStHype) {
        mockStHype = MockStHype(payable(_mockStHype));
    }

    receive() external payable {}

    function getBurnIds(address /*account*/ ) external pure override returns (uint256[] memory) {
        // not implemented
        return new uint256[](0);
    }

    function redeemable(uint256 /*_burnId*/ ) external pure override returns (bool) {
        // not implemented
        return false;
    }

    function mint(address to, string memory /*communityCode*/ ) external payable override returns (uint256) {
        mockStHype.mint{value: msg.value}(to);
        return msg.value;
    }

    function burnAndRedeemIfPossible(address to, uint256 amount, string memory /*_communityCode*/ )
        external
        override
        returns (uint256)
    {
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

    function redeem(uint256 /*_burnId*/ ) external override {
        // not implemented
    }
}
