// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {IWETH9} from "src/interfaces/IWETH9.sol";
import {HAMM} from "src/HAMM.sol";
import {WithdrawalModule} from "src/WithdrawalModule.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";

contract HAMMTest is Test {
    HAMM hamm;
    WithdrawalModule withdrawalModule;

    ProtocolFactory protocolFactory;

    IWETH9 weth;
    ERC20Mock token0;

    MockOverseer overseer;

    address public poolFeeRecipient1 = makeAddr("POOL_FEE_RECIPIENT_1");
    address public poolFeeRecipient2 = makeAddr("POOL_FEE_RECIPIENT_2");

    address public owner = makeAddr("OWNER");

    function setUp() public {
        overseer = new MockOverseer();

        protocolFactory = new ProtocolFactory(address(this));

        withdrawalModule = new WithdrawalModule(address(overseer), address(this));

        token0 = new ERC20Mock();

        hamm = new HAMM(
            address(token0),
            address(weth),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModule)
        );
        withdrawalModule.setHAMM(address(hamm));
    }

    function testHello() public {}
}
