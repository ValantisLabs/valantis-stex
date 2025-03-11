// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXLens} from "src/STEXLens.sol";

contract STEXLensDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        address stexLens = address(new STEXLens());

        console.log("Deployed STEX Lens: ", stexLens);

        vm.stopBroadcast();
    }
}
