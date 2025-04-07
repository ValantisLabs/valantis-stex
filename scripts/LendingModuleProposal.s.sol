// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {AaveLendingModule} from "src/AaveLendingModule.sol";
import {STEXAMM} from "src/STEXAMM.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {WithdrawalModuleKeeper} from "src/owner/WithdrawalModuleKeeper.sol";
import {WithdrawalModuleManager} from "src/owner/WithdrawalModuleManager.sol";

contract LendingModuleProposalScript is Script, Test {
    function run() external {
        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // stHYPE
        address token0 = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        // Valantis Protocol Factory
        address protocolFactory = 0x7E028ac56cB2AF75292F3D967978189698C24732;

        stHYPEWithdrawalModule withdrawalModule = stHYPEWithdrawalModule(
            payable(0x40Ba056B004Edd0b572509A1276Fd8530cf2bb7f)
        );

        STEXAMM stex = STEXAMM(
            payable(0x39694eFF3b02248929120c73F90347013Aec834d)
        );
        assertEq(stex.owner(), ownerMultisig);

        address pool = stex.pool();
        console.log("STEX sovereign pool: ", pool);

        console.log("STEX AMM: ", address(stex));

        WithdrawalModuleKeeper keeper = WithdrawalModuleKeeper(
            0x0Aef1eAAd539C16292faEB16D3F4AB5842F0aa6c
        );
        assertEq(keeper.owner(), ownerMultisig);

        WithdrawalModuleManager manager = WithdrawalModuleManager(
            0x80c7f89398160fCD9E74519f63F437459E5d02E2
        );
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));

        AaveLendingModule lendingModule = AaveLendingModule(
            0x36baFeB0f12A13Ca579ED4080D95AC74f59e98e0
        );

        // Simulate proposal
        assertEq(lendingModule.assetBalance(), 0);

        //vm.startPrank(address(manager));
        /*withdrawalModule.proposeLendingModule(address(lendingModule), 3 days);
        (
            address lendingModuleProposed,
            uint256 startTimestamp
        ) = withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(lendingModule));
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.warp(block.timestamp + 3 days);*/

        /*withdrawalModule.setProposedLendingModule();
        assertEq(
            address(withdrawalModule.lendingModule()),
            address(lendingModule)
        );

        withdrawalModule.supplyToken1ToLendingPool(10 ether);
        assertEq(lendingModule.assetBalance(), 10 ether);*/
        //vm.stopPrank();

        // Generate payload for `proposeLendingModule`
        /*vm.startPrank(ownerMultisig);

        bytes memory payload = abi.encodeWithSelector(
            stHYPEWithdrawalModule.proposeLendingModule.selector,
            address(lendingModule),
            3 days
        );
        bytes memory managerPayload = abi.encodeWithSelector(
            WithdrawalModuleManager.call.selector,
            address(withdrawalModule),
            payload
        );
        console.log("payload to withdrawalModule manager: ");
        console.logBytes(managerPayload);

        (bool success, ) = address(manager).call(managerPayload);
        assertTrue(success);
        (
            address lendingModuleProposed,
            uint256 startTimestamp
        ) = withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(lendingModule));
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.stopPrank();*/

        // Generate payload for `setProposedLendingModule`
        vm.startPrank(ownerMultisig);

        bytes memory payload = abi.encodeWithSelector(
            stHYPEWithdrawalModule.setProposedLendingModule.selector
        );
        bytes memory managerPayload = abi.encodeWithSelector(
            WithdrawalModuleManager.call.selector,
            address(withdrawalModule),
            payload
        );
        console.log("payload to withdrawalModule manager: ");
        console.logBytes(managerPayload);

        (bool success, ) = address(manager).call(managerPayload);
        assertTrue(success);

        assertEq(
            address(withdrawalModule.lendingModule()),
            address(lendingModule)
        );

        vm.stopPrank();

        //withdrawalModule.supplyToken1ToLendingPool(10 ether);
        //assertEq(lendingModule.assetBalance(), 10 ether);
    }
}
