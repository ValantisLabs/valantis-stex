// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {MultiMarketLendingModule} from "src/lending-modules/MultiMarketLendingModule.sol";
import {MultiMarketLendingModuleManager} from "src/owner/MultiMarketLendingModuleManager.sol";
import {MultiMarketLendingModuleKeeper} from "src/owner/MultiMarketLendingModuleKeeper.sol";
import {ERC4626LendingModule} from "src/lending-modules/ERC4626LendingModule.sol";
import {AaveLendingModule} from "src/lending-modules/AaveLendingModule.sol";
import {kHYPEWithdrawalModule} from "src/withdrawal-modules/kHYPEWithdrawalModule.sol";

contract kHYPESTEXMultiMarketLendingDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        //vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        kHYPEWithdrawalModule withdrawalModule = kHYPEWithdrawalModule(
            payable(0xd939975c3b24f5Cc8F5cd794204378a5A34e55aa)
        );

        // Uncomment to deploy MultiMarketLendingModule
        /*MultiMarketLendingModule multiLendingModule = new MultiMarketLendingModule(
                token1, // asset
                deployerAddress, // owner role
                address(withdrawalModule), // manager role (withdrawal module)
                ownerMultisig, // token sweep manager role
                2_000 // 20% fee on net yield
            );*/
        MultiMarketLendingModule multiLendingModule = MultiMarketLendingModule(
            0xdFcAeD3ff2C15dd5d95B3191670F21E73f21c22F
        );
        assertEq(multiLendingModule.asset(), token1);
        assertEq(multiLendingModule.manager(), address(withdrawalModule));
        assertEq(multiLendingModule.tokenSweepManager(), ownerMultisig);
        assertEq(multiLendingModule.managerFeeBips(), 2_000);

        // Uncomment for deployment of HypurrFi Aave Lending Module
        /*AaveLendingModule lendingModule = new AaveLendingModule(
            0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b, // AAVE V3 pool
            0x7C97cd7B57b736c6AD74fAE97C0e21e856251dcf, // aWHYPE
            token1, // WHYPE
            address(multiLendingModule), // owner
            ownerMultisig, // tokenSweepManager
            2
        );*/
        AaveLendingModule hypurrFiLendingModule = AaveLendingModule(
            0x4f4Da3703ecf88a885fe20A3B5c4C2581Ff4ED28
        );
        assertEq(
            address(hypurrFiLendingModule.pool()),
            0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b
        );
        assertEq(
            hypurrFiLendingModule.yieldToken(),
            0x7C97cd7B57b736c6AD74fAE97C0e21e856251dcf
        );
        assertEq(hypurrFiLendingModule.owner(), address(multiLendingModule));
        assertEq(hypurrFiLendingModule.tokenSweepManager(), ownerMultisig);
        assertEq(hypurrFiLendingModule.referralCode(), 2);

        // Uncomment for deployment of HyperLend Aave Lending Module
        /*AaveLendingModule hyperLendLendingModule = new AaveLendingModule(
            0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b, // Aave V3 Pool
            0x0D745EAA9E70bb8B6e2a0317f85F1d536616bD34, // Yield Token
            token1, // WHYPE
            address(multiLendingModule), // owner
            ownerMultisig, // tokenSweepManager
            0
        );*/
        AaveLendingModule hyperLendLendingModule = AaveLendingModule(
            0x1D79F0e8F7B03071957ebC677148CFBb99dEe357
        );
        assertEq(
            address(hyperLendLendingModule.pool()),
            0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b
        );
        assertEq(
            hyperLendLendingModule.yieldToken(),
            0x0D745EAA9E70bb8B6e2a0317f85F1d536616bD34
        );
        assertEq(hyperLendLendingModule.owner(), address(multiLendingModule));
        assertEq(hyperLendLendingModule.tokenSweepManager(), ownerMultisig);
        assertEq(hyperLendLendingModule.referralCode(), 0);

        // Uncomment for deployment of Felix Lending Module
        /*ERC4626LendingModule felixLendingModule = new ERC4626LendingModule(
            0x2900ABd73631b2f60747e687095537B673c06A76, // ERC4626 vault
            address(multiLendingModule), // owner
            ownerMultisig // tokenSweepManager
        );*/
        ERC4626LendingModule felixLendingModule = ERC4626LendingModule(
            0x33d60CAF7C70Fc4cB5AfF3Ae7f31fCdE74398D13
        );
        assertEq(
            address(felixLendingModule.vault()),
            0x2900ABd73631b2f60747e687095537B673c06A76
        );
        assertEq(
            felixLendingModule.asset(),
            token1 // WHYPE
        );
        assertEq(felixLendingModule.owner(), address(multiLendingModule));
        assertEq(felixLendingModule.tokenSweepManager(), ownerMultisig);

        // Uncomment for deployment of Hyperbeat Morpho Lending Module
        /*ERC4626LendingModule hyperbeatLendingModule = new ERC4626LendingModule(
            0xd19e3d00f8547f7d108abFD4bbb015486437B487, // ERC4626 vault
            address(multiLendingModule), // owner
            ownerMultisig // tokenSweepManager
        );*/
        ERC4626LendingModule hyperbeatLendingModule = ERC4626LendingModule(
            0x269B88Fa6545e117171106439CcDF38d706DF2d8
        );
        /*assertEq(
            address(hyperbeatLendingModule.vault()),
            0xd19e3d00f8547f7d108abFD4bbb015486437B487
        );
        assertEq(
            hyperbeatLendingModule.asset(),
            token1 // WHYPE
        );
        assertEq(hyperbeatLendingModule.owner(), address(multiLendingModule));
        assertEq(hyperbeatLendingModule.tokenSweepManager(), ownerMultisig);*/

        // Initialize multi-market lending module
        /*address[] memory lendingModuleArray = new address[](4);
        lendingModuleArray[0] = address(hypurrFiLendingModule);
        lendingModuleArray[1] = address(hyperLendLendingModule);
        lendingModuleArray[2] = address(felixLendingModule);
        lendingModuleArray[3] = address(hyperbeatLendingModule);

        MultiMarketLendingModule.LendingModuleConfig[]
            memory lendingModuleConfigArray = new MultiMarketLendingModule.LendingModuleConfig[](
                4
            );
        lendingModuleConfigArray[0] = MultiMarketLendingModule
            .LendingModuleConfig({
                depositWeightBips: 3_000,
                withdrawWeightBips: 3_000
            });
        lendingModuleConfigArray[1] = MultiMarketLendingModule
            .LendingModuleConfig({
                depositWeightBips: 3_700,
                withdrawWeightBips: 3_700
            });
        lendingModuleConfigArray[2] = MultiMarketLendingModule
            .LendingModuleConfig({
                depositWeightBips: 3_000,
                withdrawWeightBips: 3_000
            });
        lendingModuleConfigArray[3] = MultiMarketLendingModule
            .LendingModuleConfig({
                depositWeightBips: 300,
                withdrawWeightBips: 300
            });

        multiLendingModule.initialize(
            lendingModuleArray,
            lendingModuleConfigArray
        );*/

        // Set deposit weights
        /*uint16[] memory depositWeights = new uint16[](4);
        depositWeights[0] = 3_000;
        depositWeights[1] = 3_700;
        depositWeights[2] = 3_300;
        depositWeights[3] = 0;

        multiLendingModule.setDepositWeights(depositWeights);*/

        // Set withdraw weights
        /*uint16[] memory withdrawWeights = new uint16[](4);
        withdrawWeights[0] = 3_000;
        withdrawWeights[1] = 3_700;
        withdrawWeights[2] = 3_300;
        withdrawWeights[3] = 0;

        multiLendingModule.setWithdrawWeights(withdrawWeights);*/

        // Deploy MultiMarketLendingModuleKeeper
        /*MultiMarketLendingModuleKeeper keeper = new MultiMarketLendingModuleKeeper(
                ownerMultisig
            );*/
        MultiMarketLendingModuleKeeper keeper = MultiMarketLendingModuleKeeper(
            0xeA31F3f2A024298A1f35290b6876c5993ee01cE3
        );
        assertEq(keeper.owner(), ownerMultisig);
        assertFalse(keeper.isKeeper(deployerAddress));

        // Deploy MultiMarketLendingModuleManager
        /*MultiMarketLendingModuleManager manager = new MultiMarketLendingModuleManager(
                ownerMultisig,
                address(keeper)
            );*/
        MultiMarketLendingModuleManager manager = MultiMarketLendingModuleManager(
                0x81211b64628b7e1dECf352D175a260448DA3B089
            );
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));

        // Initiate transfer of ownership from deployerAddress to manager
        //multiLendingModule.transferOwnership(address(manager));

        // Generate payload for `manager.acceptOwnership`
        /*vm.startPrank(ownerMultisig);

        bytes memory payload = abi.encodeWithSelector(
            MultiMarketLendingModuleManager.acceptOwnership.selector,
            address(multiLendingModule)
        );

        // Call `manager.acceptOwnership`
        (bool success, ) = address(manager).call(payload);
        assertTrue(success);
        assertEq(multiLendingModule.owner(), address(manager));

        console.log(
            "Payload for MultiMarketLendingModuleManager.acceptOwnership: "
        );
        console.logBytes(payload);

        vm.stopPrank();*/
        assertEq(multiLendingModule.owner(), address(manager));

        //vm.stopBroadcast();
    }
}
