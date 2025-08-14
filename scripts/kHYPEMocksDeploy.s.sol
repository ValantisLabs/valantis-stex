// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MockStakingAccountant} from "src/mocks/kinetiq/MockStakingAccountant.sol";
import {MockStakingManager} from "src/mocks/kinetiq/MockStakingManager.sol";

contract kHYPEMocksDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock kHYPE
        //ERC20Mock token0 = new ERC20Mock();
        ERC20Mock token0 = ERC20Mock(
            0x95DD90fDeFfd53631409A1946B96225Ed3bc30B2
        );

        // Deploy mock Staking Accountant
        /*MockStakingAccountant stakingAccountant = new MockStakingAccountant(
            address(token0)
        );*/
        MockStakingAccountant stakingAccountant = MockStakingAccountant(
            0xD9CDA4e095f74E284FF38B8276E7aeA3ca9a25c2
        );
        // Deploy mock Staking Manager
        /*MockStakingManager stakingManager = new MockStakingManager(
            address(stakingAccountant),
            address(token0)
        );*/
        MockStakingManager stakingManager = MockStakingManager(
            0x0245549783cCb543bC98D3557b42512ac8d1cdc4
        );

        // Set unstaking fee in bips
        //stakingManager.setUnstakeFeeRate(10);
        assertEq(stakingManager.unstakeFeeRate(), 10);

        // Mint kHYPE
        //stakingManager.stake{value: 0.2 ether}();

        vm.stopBroadcast();
    }
}
