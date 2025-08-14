// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {StepwiseFeeModule} from "src/swap-fee-modules/StepwiseFeeModule.sol";
import {StepwiseFeeModuleKeeper} from "src/owner/StepwiseFeeModuleKeeper.sol";

contract StepwiseFeeModuleDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        STEXAMM stex = STEXAMM(
            payable(0xbf747D2959F03332dbd25249dB6f00F62c6Cb526)
        );

        // Uncomment to deploy Swap Fee Module
        /*StepwiseFeeModule swapFeeModule = new StepwiseFeeModule(
            deployerAddress
        );
        assertEq(swapFeeModule.owner(), deployerAddress);*/
        StepwiseFeeModule swapFeeModule = StepwiseFeeModule(
            0x14EFe613b8a1fce7142286D0bC70723519bc4485
        );

        // Uncomment to deploy Keeper
        /*StepwiseFeeModuleKeeper keeper = new StepwiseFeeModuleKeeper(
            deployerAddress
        );*/
        StepwiseFeeModuleKeeper keeper = StepwiseFeeModuleKeeper(
            0x623cD8e6CA491A30BeE10Cb91034B059a162C007
        );

        // Uncomment to whitelist a keeper address
        address keeperEOA = 0x35826836418Ece9D00e4436bb91CA9a9d5136b30;
        //keeper.setKeeper(keeperEOA);
        assertTrue(keeper.isKeeper(keeperEOA));

        // Uncomment to remove a keeper address
        //keeper.removeKeeper(deployerAddress);
        //assertFalse(keeper.isKeeper(deployerAddress));

        // Uncomment to transfer ownership of Keeper
        //keeper.transferOwnership(ownerMultisig);
        assertEq(keeper.owner(), ownerMultisig);

        // Uncomment to generate payload to propose Swap Fee Module update under timelock
        /*vm.startPrank(ownerMultisig);
        bytes memory swapFeeModuleProposalPayload = abi.encodeWithSelector(
            STEXAMM.proposeSwapFeeModule.selector,
            address(swapFeeModule),
            3 days
        );
        console.log("payload for swap fee module proposal: ");
        console.logBytes(swapFeeModuleProposalPayload);
        (bool success, ) = address(stex).call(swapFeeModuleProposalPayload);
        assertTrue(success);
        (address swapFeeModuleProposed, uint256 startTimestamp) = stex
            .swapFeeModuleProposal();
        assertEq(swapFeeModuleProposed, address(swapFeeModule));
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.warp(block.timestamp + 3 days);

        stex.setProposedSwapFeeModule();

        vm.stopPrank();*/

        // Uncomment to transfer ownership of Swap Fee Module
        //swapFeeModule.transferOwnership(address(keeper));
        assertEq(swapFeeModule.owner(), address(keeper));

        // Uncomment to set Swap Fee Module params
        /*{
            uint256 minThresholdToken1 = 10_000 ether;
            uint256 maxThresholdToken1 = 200_000 ether;
            uint256 numSteps = 5;
            uint32[] memory feeStepsInBipsToken0 = new uint32[](numSteps);
            feeStepsInBipsToken0[0] = 3;
            feeStepsInBipsToken0[1] = 20;
            feeStepsInBipsToken0[2] = 50;
            feeStepsInBipsToken0[3] = 200;
            feeStepsInBipsToken0[4] = 500;

            keeper.setFeeParamsToken0(
                address(swapFeeModule),
                minThresholdToken1,
                maxThresholdToken1,
                feeStepsInBipsToken0
            );
        }*/
        /*{
            uint256 minThresholdToken1 = swapFeeModule.minThresholdToken1();
            uint256 maxThresholdToken1 = swapFeeModule.maxThresholdToken1();
            uint32[] memory feeStepsInBips = swapFeeModule.getToken0FeeInBips();

            assertEq(minThresholdToken1, 10_000 ether);
            assertEq(maxThresholdToken1, 200_000 ether);
            assertEq(feeStepsInBips[1], 20);
            assertEq(feeStepsInBips[2], 50);
            assertEq(feeStepsInBips[3], 200);
            assertEq(feeStepsInBips[4], 500);
            assertEq(swapFeeModule.numStepsToken0FeeCurve(), 5);
        }*/

        // Uncomment to set STEX AMM's pool in Swap Fee Module
        address pool = stex.pool();
        //swapFeeModule.setPool(pool);
        assertEq(swapFeeModule.pool(), pool);

        vm.stopBroadcast();
    }
}
