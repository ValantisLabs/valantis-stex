// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXLens} from "src/STEXLens.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";

contract STEXLensDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Uncomment to deploy STEX Lens
        //address stexLens = address(new STEXLens());
        STEXLens stexLens = STEXLens(
            0x40FeebdE4e98BbD31c07698A89d545482ff29E82
        );

        vm.stopBroadcast();
    }
}
