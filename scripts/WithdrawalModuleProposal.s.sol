// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {WithdrawalModuleManager} from "src/owner/WithdrawalModuleManager.sol";
import {WithdrawalModuleKeeper} from "src/owner/WithdrawalModuleKeeper.sol";

contract WithdrawalModuleProposalScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        //vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // stHYPE
        address token0 = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        // Valantis Protocol Factory
        address protocolFactory = 0x7E028ac56cB2AF75292F3D967978189698C24732;

        // Thunderhead's Overseer
        address overseer = 0xB96f07367e69e86d6e9C3F29215885104813eeAE;

        // Previous deployment of withdrawal module (after proposal gets executed)
        stHYPEWithdrawalModule withdrawalModuleOld = stHYPEWithdrawalModule(
            payable(0x40Ba056B004Edd0b572509A1276Fd8530cf2bb7f)
        );

        // Uncomment for deployment of Withdrawal Module
        /*stHYPEWithdrawalModule withdrawalModule = new stHYPEWithdrawalModule(
            overseer,
            deployerAddress
        );
        assertEq(withdrawalModule.owner(), deployerAddress);
        assertEq(withdrawalModule.overseer(), overseer);*/
        stHYPEWithdrawalModule withdrawalModule = stHYPEWithdrawalModule(
            payable(0x69e487aA3132708d08a979b2d07c5119Bb77F698)
        );

        STEXAMM stex = STEXAMM(
            payable(0x39694eFF3b02248929120c73F90347013Aec834d)
        );
        assertEq(stex.owner(), ownerMultisig);

        ISovereignPool pool = ISovereignPool(stex.pool());

        vm.startPrank(ownerMultisig);

        // Uncomment to set STEX AMM in withdrawal module
        /*withdrawalModule.setSTEX(address(stex));
        assertEq(withdrawalModule.stex(), address(stex));
        assertEq(withdrawalModule.pool(), address(pool));*/

        // Uncomment to propose the new withdrawal module
        /*bytes memory payload = abi.encodeWithSelector(
            STEXAMM.proposeWithdrawalModule.selector,
            address(withdrawalModule)
        );
        console.log("payload for stex.proposeWithdrawalModule: ");
        console.logBytes(payload);

        stex.proposeWithdrawalModule(address(withdrawalModule));
        (address swapFeeModuleNew, uint256 timestamp) = stex
            .withdrawalModuleProposal();
        assertEq(swapFeeModuleNew, address(withdrawalModule));
        assertEq(timestamp, block.timestamp + 7 days);*/

        // Uncomment to update to the new withdrawal module after timelock
        // Ensure that all token1 is sent back to the pool before applying the proposal
        /*assertLt(
            withdrawalModuleOld.amountToken1LendingPool(),
            1e16,
            "Must withdraw token1 from old withdrawal module's lending pool"
        );
        // Ensure that all pending LP withdrawals from old module are processed
        assertEq(
            withdrawalModuleOld.amountToken1PendingLPWithdrawal(),
            0,
            "There are pending LP withdrawals in old withdrawal module"
        );
        assertEq(withdrawalModuleOld.amountToken0PendingUnstaking(), 0);
        // Ensure that `update` does not need to be called
        assertEq(
            address(withdrawalModuleOld).balance,
            withdrawalModuleOld.amountToken1ClaimableLPWithdrawal(),
            "Need to call update in old withdrawal module"
        );

        bytes memory payloadSetWithdrawalModule = abi.encodeWithSelector(
            STEXAMM.setProposedWithdrawalModule.selector
        );
        console.log("payload for stex.setProposedWithdrawalModule");
        console.logBytes(payloadSetWithdrawalModule);*/

        //vm.warp(block.timestamp + 7 days);
        //stex.setProposedWithdrawalModule();
        assertEq(stex.withdrawalModule(), address(withdrawalModule));

        vm.stopPrank();

        WithdrawalModuleKeeper keeper = WithdrawalModuleKeeper(
            0x0Aef1eAAd539C16292faEB16D3F4AB5842F0aa6c
        );
        assertEq(keeper.owner(), ownerMultisig);

        WithdrawalModuleManager manager = WithdrawalModuleManager(
            0x80c7f89398160fCD9E74519f63F437459E5d02E2
        );
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));

        // Uncomment to transfer ownership of withdrawal module to manager contract
        //withdrawalModule.transferOwnership(address(manager));
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

        // Uncomment for deployment of Aave Lending Module
        /*{
            AaveLendingModule lendingModule = new AaveLendingModule(
                0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b, // AAVE V3 pool
                0x7C97cd7B57b736c6AD74fAE97C0e21e856251dcf, // aWHYPE
                stex.token1(), // WHYPE
                address(withdrawalModule), // owner
                ownerMultisig, // tokenSweepManager
                2
            );
            assertEq(
                address(lendingModule.pool()),
                0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b
            );
            assertEq(
                lendingModule.yieldToken(),
                0x7C97cd7B57b736c6AD74fAE97C0e21e856251dcf
            );
            assertEq(lendingModule.owner(), address(withdrawalModule));
            assertEq(lendingModule.tokenSweepManager(), ownerMultisig);
            assertEq(lendingModule.referralCode(), 2);
        }*/

        //vm.stopBroadcast();
    }
}
