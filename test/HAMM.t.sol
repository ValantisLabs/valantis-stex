// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {IWETH9} from "src/interfaces/IWETH9.sol";
import {HAMM} from "src/HAMM.sol";
import {WithdrawalModule} from "src/WithdrawalModule.sol";

contract HAMMTest is Test {
    HAMM hamm;
    WithdrawalModule withdrawalModule;

    ProtocolFactory protocolFactory;

    IWETH9 weth;
    ERC20Mock token0;
}
