// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {STEXRatioSwapFeeModule} from "src/STEXRatioSwapFeeModule.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";
import {WithdrawalModuleManager} from "src/owner/WithdrawalModuleManager.sol";
import {WithdrawalModuleKeeper} from "src/owner/WithdrawalModuleKeeper.sol";

contract STEXDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

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

        // Uncomment to deploy Swap Fee Module
        /*STEXRatioSwapFeeModule swapFeeModule = new STEXRatioSwapFeeModule(
            deployerAddress
        );
        assertEq(swapFeeModule.owner(), deployerAddress);*/
        STEXRatioSwapFeeModule swapFeeModule = STEXRatioSwapFeeModule(
            0x72cB15FbCc74ca3Ef4E0AAd43fC77aCD82D182f4
        );
        //swapFeeModule.transferOwnership(ownerMultisig);
        assertEq(swapFeeModule.owner(), ownerMultisig);

        // Uncomment to set Swap Fee Module params
        /*{
            uint32 minThresholdRatioBips = 3_000;
            uint32 maxThresholdRatioBips = 7_000;
            uint32 feeMinBips = 5;
            uint32 feeMaxBips = 40;

            bytes memory payload = abi.encodeWithSelector(
                STEXRatioSwapFeeModule.setSwapFeeParams.selector,
                minThresholdRatioBips,
                maxThresholdRatioBips,
                feeMinBips,
                feeMaxBips
            );

            console.log("payload for swapFeeModule.setSwapFeeParams: ");
            console.logBytes(payload);

            // swapFeeModule.setSwapFeeParams(
            //    minThresholdRatioBips,
            //    maxThresholdRatioBips,
            //    feeMinBips,
            //    feeMaxBips
            // );
        }*/
        {
            (
                uint32 minThresholdRatioBips,
                uint32 maxThresholdRatioBips,
                uint32 feeMinBips,
                uint32 feeMaxBips
            ) = swapFeeModule.feeParams();
            assertEq(minThresholdRatioBips, 3_000);
            assertEq(maxThresholdRatioBips, 7_000);
            assertEq(feeMinBips, 5);
            assertEq(feeMaxBips, 40);
        }

        // Uncomment for deployment of Withdrawal Module
        /*stHYPEWithdrawalModule withdrawalModule = new stHYPEWithdrawalModule(
            overseer,
            deployerAddress
        );
        assertEq(withdrawalModule.owner(), deployerAddress);
        assertEq(withdrawalModule.overseer(), overseer);*/
        stHYPEWithdrawalModule withdrawalModule = stHYPEWithdrawalModule(
            payable(0x1da0eA7f6464D715b0DA6922Aeb45c382Cc8Ab15)
        );

        // Uncomment for deployment of STEX AMM
        /*STEXAMM stex = new STEXAMM(
            "stHYPE AMM",
            "stHYPE AMM LP",
            token0,
            token1,
            address(swapFeeModule),
            protocolFactory,
            0xA2666B4dD1242Def4c3cf5731a85Aa8457fe01C1, // feeRecipient1
            0x24577bacbd3B74C4065226a97e789023bba3296e, // feeRecipient2
            deployerAddress, // owner
            address(withdrawalModule),
            10
        );
        assertEq(stex.owner(), deployerAddress);*/
        STEXAMM stex = STEXAMM(
            payable(0xE20725BEa0aF2b125Fe21882385275cDbfA94298)
        );
        //stex.transferOwnership(ownerMultisig);
        assertEq(stex.owner(), ownerMultisig);

        address pool = stex.pool();
        console.log("STEX sovereign pool: ", pool);

        // Uncomment to set STEX's pool manager fees in bips
        // 20%
        uint256 managerFeeBips = 2_000;

        bytes memory data = abi.encodeWithSelector(
            STEXAMM.setPoolManagerFeeBips.selector,
            managerFeeBips
        );
        //console.log("payload for stex.setPoolManagerFeeBips: ");
        //console.logBytes(data);

        //stex.setPoolManagerFeeBips(2_000);

        // Uncomment to set STEX AMM's pool in Swap Fee Module
        //swapFeeModule.setPool(pool);
        assertEq(swapFeeModule.pool(), pool);

        // Uncomment to set STEX AMM in withdrawal module
        //withdrawalModule.setSTEX(address(stex));
        assertEq(withdrawalModule.stex(), address(stex));
        assertEq(withdrawalModule.pool(), pool);

        console.log("STEX AMM: ", address(stex));

        // Uncomment for deployment of Deposit Wrapper
        /*DepositWrapper depositWrapper = new DepositWrapper(
            stex.token1(),
            address(stex)
        );*/
        DepositWrapper depositWrapper = DepositWrapper(
            payable(0xa731B781228553be3166cE4C7A63B2f40b1dF956)
        );

        // Uncomment for deployment of withdrawal module's keeper
        /*WithdrawalModuleKeeper keeper = new WithdrawalModuleKeeper(
            deployerAddress
        );
        assertEq(keeper.owner(), deployerAddress);
        console.log("keeper deployed: ", address(keeper));*/
        WithdrawalModuleKeeper keeper = WithdrawalModuleKeeper(
            0x0Aef1eAAd539C16292faEB16D3F4AB5842F0aa6c
        );
        /*address keeperEOA = 0x6Fa0b094b71EF7fcA715177242682bdf1954e2e8;
        keeper.setKeeper(keeperEOA);
        assertTrue(keeper.isKeeper(keeperEOA));*/
        //keeper.transferOwnership(ownerMultisig);
        assertEq(keeper.owner(), ownerMultisig);

        // Uncomment for deployment of withdrawal module's owner
        /*WithdrawalModuleManager manager = new WithdrawalModuleManager(
            deployerAddress,
            address(keeper)
        );*/
        //assertEq(manager.owner(), deployerAddress);
        //assertEq(manager.keeper(), address(keeper));
        WithdrawalModuleManager manager = WithdrawalModuleManager(
            0x80c7f89398160fCD9E74519f63F437459E5d02E2
        );
        //manager.transferOwnership(ownerMultisig);
        assertEq(manager.owner(), ownerMultisig);
        //withdrawalModule.transferOwnership(address(manager));
        assertEq(withdrawalModule.owner(), address(manager));

        vm.stopBroadcast();
    }
}
