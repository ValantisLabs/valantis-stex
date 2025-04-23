// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {WithdrawalModuleManager} from "src/owner/WithdrawalModuleManager.sol";
import {WithdrawalModuleKeeper} from "src/owner/WithdrawalModuleKeeper.sol";

contract WithdrawalModuleStakingScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        //vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        stHYPEWithdrawalModule withdrawalModule = stHYPEWithdrawalModule(
            payable(0x69e487aA3132708d08a979b2d07c5119Bb77F698)
        );

        STEXAMM stex = STEXAMM(
            payable(0x39694eFF3b02248929120c73F90347013Aec834d)
        );
        assertEq(stex.owner(), ownerMultisig);

        ISovereignPool pool = ISovereignPool(stex.pool());

        assertEq(stex.withdrawalModule(), address(withdrawalModule));

        WithdrawalModuleKeeper keeper = WithdrawalModuleKeeper(
            0x0Aef1eAAd539C16292faEB16D3F4AB5842F0aa6c
        );
        assertEq(keeper.owner(), ownerMultisig);

        WithdrawalModuleManager manager = WithdrawalModuleManager(
            0x80c7f89398160fCD9E74519f63F437459E5d02E2
        );
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));
        assertEq(withdrawalModule.owner(), address(manager));

        // Uncomment to test withdrawal module's `stakeToken1`
        /*vm.startPrank(ownerMultisig);

        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();
        uint256 amountToStake = 50_000 ether;
        string memory communityCode = "0x6e616e73656e";
        bytes memory payloadStakeToken1 = abi.encodeWithSelector(
            stHYPEWithdrawalModule.stakeToken1.selector,
            amountToStake,
            communityCode
        );
        bytes memory managerPayload = abi.encodeWithSelector(
            WithdrawalModuleManager.call.selector,
            address(withdrawalModule),
            payloadStakeToken1
        );
        console.log(
            "payload to withdrawalModule manager for withdrawalModule.stakeToken1: "
        );
        console.logBytes(managerPayload);

        (bool success, ) = address(manager).call(managerPayload);
        assertTrue(success);

        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();
        assertEq(postReserve0, preReserve0 + amountToStake);
        assertEq(postReserve1, preReserve1 - amountToStake);

        vm.stopPrank();*/

        //vm.stopBroadcast();
    }
}
