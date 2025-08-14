// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {kHYPEWithdrawalModule} from "src/withdrawal-modules/kHYPEWithdrawalModule.sol";
//import {kHYPEWithdrawalModuleKeeper} from "src/owner/kHYPEWithdrawalModuleKeeper.sol";
//import {kHYPEWithdrawalModuleManager} from "src/owner/kHYPEWithdrawalModuleManager.sol";
import {RebalanceModule} from "src/RebalanceModule.sol";

contract kHYPERebalanceModuleDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // kHYPE withdrawal module
        kHYPEWithdrawalModule withdrawalModule = kHYPEWithdrawalModule(
            payable(0xd939975c3b24f5Cc8F5cd794204378a5A34e55aa)
        );

        address pool = withdrawalModule.pool();

        /*RebalanceModule rebalanceModule = new RebalanceModule(
            address(withdrawalModule),
            pool,
            ownerMultisig
        );*/
        RebalanceModule rebalanceModule = RebalanceModule(
            0xbfc56efbdB55C1bF0A3103Fd04C98dD0D70f13B9
        );

        assertEq(
            address(rebalanceModule.withdrawalModule()),
            address(withdrawalModule)
        );
        assertEq(address(rebalanceModule.pool()), pool);
        assertEq(rebalanceModule.owner(), ownerMultisig);

        vm.stopBroadcast();
    }
}
