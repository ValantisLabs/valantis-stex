// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {StepwiseFeeModule} from "src/swap-fee-modules/StepwiseFeeModule.sol";
import {kHYPEWithdrawalModule} from "src/withdrawal-modules/kHYPEWithdrawalModule.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";
import {kHYPEWithdrawalModuleManager} from "src/owner/kHYPEWithdrawalModuleManager.sol";
import {kHYPEWithdrawalModuleKeeper} from "src/owner/kHYPEWithdrawalModuleKeeper.sol";
import {ERC4626LendingModule} from "src/lending-modules/ERC4626LendingModule.sol";
import {AaveLendingModule} from "src/lending-modules/AaveLendingModule.sol";

contract kHYPESTEXDeployScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // kHYPE
        address token0 = 0xfD739d4e423301CE9385c1fb8850539D657C296D;
        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        // Valantis Protocol Factory
        address protocolFactory = 0x7E028ac56cB2AF75292F3D967978189698C24732;

        // Kinetiq Staking Manager
        //address stakingManager = 0x393D0B87Ed38fc779FD9611144aE649BA6082109;
        // Kinetiq Staking Accountant
        //address stakingAccountant = 0x9209648Ec9D448EF57116B73A2f081835643dc7A;

        // Uncomment to deploy Swap Fee Module
        /*StepwiseFeeModule swapFeeModule = new StepwiseFeeModule(
            deployerAddress
        );
        assertEq(swapFeeModule.owner(), deployerAddress);*/
        StepwiseFeeModule swapFeeModule = StepwiseFeeModule(
            0x14EFe613b8a1fce7142286D0bC70723519bc4485
        );
        // Uncomment to generate payload to propose Swap Fee Module update under timelock
        /*bytes memory swapFeeModuleProposalPayload = abi.encodeWithSelector(
            STEXAMM.proposeSwapFeeModule.selector,
            address(swapFeeModule),
            3 days
        );
        console.log("payload for swap fee module proposal: ");
        console.logBytes(swapFeeModuleProposalPayload);*/

        // Uncomment to transfer ownership of Swap Fee Module
        //swapFeeModule.transferOwnership(ownerMultisig);
        //assertEq(swapFeeModule.owner(), ownerMultisig);

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

            swapFeeModule.setFeeParamsToken0(
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

        // Uncomment for deployment of Withdrawal Module
        /*kHYPEWithdrawalModule withdrawalModule = new kHYPEWithdrawalModule(
            stakingAccountant,
            stakingManager,
            deployerAddress
        );
        assertEq(withdrawalModule.owner(), deployerAddress);
        assertEq(withdrawalModule.overseer(), stakingManager);
        assertEq(withdrawalModule.stakingAccountant(), stakingAccountant);
        assertEq(withdrawalModule.stakingManager(), stakingManager);*/
        kHYPEWithdrawalModule withdrawalModule = kHYPEWithdrawalModule(
            payable(0xd939975c3b24f5Cc8F5cd794204378a5A34e55aa)
        );

        // Uncomment for deployment of STEX AMM
        /*STEXAMM stex = new STEXAMM(
            "kHYPE AMM",
            "kHYPE AMM LP",
            token0,
            token1,
            address(swapFeeModule),
            protocolFactory,
            0xA2666B4dD1242Def4c3cf5731a85Aa8457fe01C1, // feeRecipient1
            0xA2666B4dD1242Def4c3cf5731a85Aa8457fe01C1, // feeRecipient2
            deployerAddress, // owner
            address(withdrawalModule),
            0
        );
        assertEq(stex.owner(), deployerAddress);*/
        STEXAMM stex = STEXAMM(
            payable(0xbf747D2959F03332dbd25249dB6f00F62c6Cb526)
        );
        //stex.transferOwnership(ownerMultisig);
        assertEq(stex.owner(), ownerMultisig);

        address pool = stex.pool();
        console.log("STEX sovereign pool: ", pool);

        // Uncomment to set STEX's pool manager fees in bips
        // 20%
        //uint256 managerFeeBips = 2_000;

        /*bytes memory data = abi.encodeWithSelector(
            STEXAMM.setPoolManagerFeeBips.selector,
            managerFeeBips
        );*/
        //console.log("payload for stex.setPoolManagerFeeBips: ");
        //console.logBytes(data);

        //stex.setPoolManagerFeeBips(managerFeeBips);

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
        );
        DepositWrapper depositWrapper = DepositWrapper(
            payable(0xA2918c869e352ADdd5b1f9f12cDe5672B23f139d)
        );*/

        // Uncomment for deployment of withdrawal module's keeper
        /*kHYPEWithdrawalModuleKeeper keeper = new kHYPEWithdrawalModuleKeeper(
            deployerAddress
        );
        assertEq(keeper.owner(), deployerAddress);
        console.log("keeper deployed: ", address(keeper));*/
        kHYPEWithdrawalModuleKeeper keeper = kHYPEWithdrawalModuleKeeper(
            0x0A3495d86DbB7dB0f59c54747bc81C321C295e8c
        );
        //address keeperEOA = 0xFBFfd0f718E8f3Bb0c5Dcd0678529609ba4A398E;
        //keeper.setKeeper(keeperEOA);
        //assertTrue(keeper.isKeeper(keeperEOA));
        //keeper.transferOwnership(ownerMultisig);
        assertEq(keeper.owner(), ownerMultisig);

        // Uncomment for deployment of withdrawal module's owner
        /*kHYPEWithdrawalModuleManager manager = new kHYPEWithdrawalModuleManager(
            deployerAddress,
            address(keeper)
        );
        assertEq(manager.owner(), deployerAddress);
        assertEq(manager.keeper(), address(keeper));*/
        kHYPEWithdrawalModuleManager manager = kHYPEWithdrawalModuleManager(
            0xE100cC3B7bCD133381B63351868705b224537765
        );
        //manager.transferOwnership(ownerMultisig);
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));
        //withdrawalModule.transferOwnership(address(manager));
        assertEq(withdrawalModule.owner(), address(manager));

        // Uncomment for deployment of ERC4626 Lending Module
        /*{
            ERC4626LendingModule lendingModule = new ERC4626LendingModule(
                0x2900ABd73631b2f60747e687095537B673c06A76, // ERC4626 vault
                address(withdrawalModule), // owner
                ownerMultisig // tokenSweepManager
            );
            assertEq(
                address(lendingModule.vault()),
                0x2900ABd73631b2f60747e687095537B673c06A76
            );
            assertEq(
                lendingModule.asset(),
                stex.token1() // WHYPE
            );
            assertEq(lendingModule.owner(), address(withdrawalModule));
            assertEq(lendingModule.tokenSweepManager(), ownerMultisig);
        }*/

        // Uncomment for deployment of Aave Lending Module
        /*{
            AaveLendingModule lendingModule = new AaveLendingModule(
                0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b, // Aave V3 Pool
                0x0D745EAA9E70bb8B6e2a0317f85F1d536616bD34, // Yield Token
                stex.token1(), // WHYPE
                address(withdrawalModule), // Owner
                ownerMultisig, // Token Sweep Manager
                0 // Referral Code
            );
            assertEq(lendingModule.owner(), address(withdrawalModule));
            assertEq(lendingModule.tokenSweepManager(), ownerMultisig);
            assertEq(
                address(lendingModule.pool()),
                0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b
            );
            assertEq(
                lendingModule.yieldToken(),
                0x0D745EAA9E70bb8B6e2a0317f85F1d536616bD34
            );
            assertEq(
                lendingModule.asset(),
                0x5555555555555555555555555555555555555555
            );
        }*/

        // Uncomment to unpause STEXAMM
        /*vm.startPrank(ownerMultisig);
        bytes memory payload = abi.encodeWithSelector(STEXAMM.unpause.selector);
        console.log("payload to stex manager: ");
        console.logBytes(payload);
        stex.unpause();
        assertFalse(stex.paused());

        vm.stopPrank();*/

        vm.stopBroadcast();
    }
}
