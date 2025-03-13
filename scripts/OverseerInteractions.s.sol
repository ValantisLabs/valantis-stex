// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {IOverseer} from "src/interfaces/IOverseer.sol";
import {IWithdrawalModule} from "src/interfaces/IWithdrawalModule.sol";

contract OverseerInteractionsScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Thunderhead's Overseer
        IOverseer overseer = IOverseer(
            0xB96f07367e69e86d6e9C3F29215885104813eeAE
        );

        IWithdrawalModule withdrawalModule = IWithdrawalModule(
            0xc7267F6cc4B4f61a025A797ef03c11285E6b630C
        );

        console.log(block.timestamp);

        uint256[] memory burnIds = overseer.getBurnIds(
            address(withdrawalModule)
        );
        for (uint256 i; i < burnIds.length; i++) {
            console.log("Pending burnId for withdrawalModule: ", burnIds[i]);
        }

        //withdrawalModule.unstakeToken0Reserves(1 ether);
        //withdrawalModule.update();

        /*console.log(
            "amountToken0PendingUnstaking: ",
            withdrawalModule.amountToken0PendingUnstaking()
        );
        console.log(
            "amountToken1PendingLPWithdrawal: ",
            withdrawalModule.amountToken1PendingLPWithdrawal()
        );
        console.log(address(withdrawalModule).balance);*/

        vm.stopBroadcast();
    }
}
