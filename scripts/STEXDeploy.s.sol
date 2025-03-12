// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {STEXRatioSwapFeeModule} from "src/STEXRatioSwapFeeModule.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";

contract STEXDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // stHYPE
        address token0 = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        // Valantis Protocol Factory
        address protocolFactory = 0x27c495e778386b57e9e9F309f4cF99DFc3103e1F;

        // Thunderhead's Overseer
        address overseer = 0xB96f07367e69e86d6e9C3F29215885104813eeAE;

        // Uncomment for deployment
        /*STEXRatioSwapFeeModule swapFeeModule = new STEXRatioSwapFeeModule(
            deployerAddress
        );
        assertEq(swapFeeModule.owner(), deployerAddress);*/
        STEXRatioSwapFeeModule swapFeeModule = STEXRatioSwapFeeModule(
            0x100d51E2caD5801F787087AfE2b87C10195B9218
        );

        // Uncomment to set Swap Fee Module params
        /*{
            uint32 minThresholdRatioBips = 3_000;
            uint32 maxThresholdRatioBips = 7_000;
            uint32 feeMinBips = 1;
            uint32 feeMaxBips = 40;

            swapFeeModule.setSwapFeeParams(
                minThresholdRatioBips,
                maxThresholdRatioBips,
                feeMinBips,
                feeMaxBips
            );
        }*/

        // Uncomment for deployment
        /*stHYPEWithdrawalModule withdrawalModule = new stHYPEWithdrawalModule(
            overseer,
            deployerAddress
        );
        //assertEq(withdrawalModule.owner(), deployerAddress);
        //assertEq(withdrawalModule.overseer(), overseer);*/
        stHYPEWithdrawalModule withdrawalModule = stHYPEWithdrawalModule(
            payable(0xc7267F6cc4B4f61a025A797ef03c11285E6b630C)
        );

        // Uncomment for deployment
        /*STEXAMM stex = new STEXAMM(
            "STEX",
            "STEX LP",
            token0,
            token1,
            address(swapFeeModule),
            protocolFactory,
            deployerAddress,
            deployerAddress,
            deployerAddress,
            address(withdrawalModule),
            10
        );
        assertEq(stex.owner(), deployerAddress);*/
        STEXAMM stex = STEXAMM(
            payable(0x66416163b99265D3ADC3B54348c1F80ad34A016E)
        );

        address pool = stex.pool();

        // Uncomment to set STEX's pool in swap fee module
        /*swapFeeModule.setPool(pool);
        assertEq(swapFeeModule.pool(), pool);

        // Uncomment to set STEX in withdrawal module
        withdrawalModule.setSTEX(address(stex));
        assertEq(withdrawalModule.stex(), address(stex));

        console.log("STEX AMM: ", address(stex));*/

        // Uncomment for deployment
        /*DepositWrapper depositWrapper = new DepositWrapper(
            stex.token1(),
            address(stex)
        );*/
        DepositWrapper depositWrapper = DepositWrapper(
            payable(0x408046F07a009A5BE4A8Ed3B26A68E382513A492)
        );

        vm.stopBroadcast();
    }
}
