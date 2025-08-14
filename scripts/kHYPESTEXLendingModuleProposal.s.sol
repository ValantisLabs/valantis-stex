// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {ERC4626LendingModule} from "src/lending-modules/ERC4626LendingModule.sol";
import {AaveLendingModule} from "src/lending-modules/AaveLendingModule.sol";
import {MultiMarketLendingModule} from "src/lending-modules/MultiMarketLendingModule.sol";
import {STEXAMM} from "src/STEXAMM.sol";
import {kHYPEWithdrawalModule} from "src/withdrawal-modules/kHYPEWithdrawalModule.sol";
import {kHYPEWithdrawalModuleKeeper} from "src/owner/kHYPEWithdrawalModuleKeeper.sol";
import {kHYPEWithdrawalModuleManager} from "src/owner/kHYPEWithdrawalModuleManager.sol";

contract kHYPESTEXLendingModuleProposalScript is Script, Test {
    function run() external {
        if (block.chainid != 999) revert("Chain ID not Hyper EVM mainnet");

        // Address of owner multi-sig wallet
        address ownerMultisig = 0xe26dA5cBf101bDA4028E2B3208c32424f5D09421;

        // kHYPE
        address token0 = 0xfD739d4e423301CE9385c1fb8850539D657C296D;
        // WHYPE
        address token1 = 0x5555555555555555555555555555555555555555;

        // Valantis Protocol Factory
        address protocolFactory = 0x7E028ac56cB2AF75292F3D967978189698C24732;

        kHYPEWithdrawalModule withdrawalModule = kHYPEWithdrawalModule(
            payable(0xd939975c3b24f5Cc8F5cd794204378a5A34e55aa)
        );

        STEXAMM stex = STEXAMM(
            payable(0xbf747D2959F03332dbd25249dB6f00F62c6Cb526)
        );
        assertEq(stex.owner(), ownerMultisig);

        ISovereignPool pool = ISovereignPool(stex.pool());
        console.log("STEX sovereign pool: ", address(pool));

        console.log("STEX AMM: ", address(stex));

        kHYPEWithdrawalModuleKeeper keeper = kHYPEWithdrawalModuleKeeper(
            0x0A3495d86DbB7dB0f59c54747bc81C321C295e8c
        );
        assertEq(keeper.owner(), ownerMultisig);

        kHYPEWithdrawalModuleManager manager = kHYPEWithdrawalModuleManager(
            0xE100cC3B7bCD133381B63351868705b224537765
        );
        assertEq(manager.owner(), ownerMultisig);
        assertEq(manager.keeper(), address(keeper));

        // HyperLend Lending Module
        /*AaveLendingModule lendingModule = AaveLendingModule(
            0x78b68763294B86d451958dc01c8E6b3057645F67
        );*/
        // Multi-market lending module
        MultiMarketLendingModule lendingModule = MultiMarketLendingModule(
            0xdFcAeD3ff2C15dd5d95B3191670F21E73f21c22F
        );

        // Simulate proposal

        /*vm.startPrank(address(manager));
        withdrawalModule.proposeLendingModule(address(lendingModule), 3 days);
        (
            address lendingModuleProposed,
            uint256 startTimestamp
        ) = withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(lendingModule));
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.warp(block.timestamp + 3 days);

        withdrawalModule.setProposedLendingModule();
        assertEq(
            address(withdrawalModule.lendingModule()),
            address(lendingModule)
        );
        vm.stopPrank();*/

        // Simulate lending module deposit
        /*vm.startPrank(address(manager));
        withdrawalModule.supplyToken1ToLendingPool(100 ether);
        console.log(
            "asset balance in lending protocol: ",
            lendingModule.assetBalance()
        );
        vm.stopPrank();*/

        // Simulate lending module withdraw
        /*vm.startPrank(address(manager));
        withdrawalModule.withdrawToken1FromLendingPool(0.1 ether, address(0));
        console.log(
            "asset balance in lending protocol: ",
            lendingModule.assetBalance()
        );
        vm.stopPrank();*/

        // Generate payload for `proposeLendingModule`
        /*vm.startPrank(ownerMultisig);

        bytes memory payload = abi.encodeWithSelector(
            kHYPEWithdrawalModule.proposeLendingModule.selector,
            address(lendingModule),
            3 days
        );
        bytes memory managerPayload = abi.encodeWithSelector(
            kHYPEWithdrawalModuleManager.call.selector,
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
        /*vm.startPrank(ownerMultisig);

        bytes memory payload = abi.encodeWithSelector(
            kHYPEWithdrawalModule.setProposedLendingModule.selector
        );
        bytes memory managerPayload = abi.encodeWithSelector(
            kHYPEWithdrawalModuleManager.call.selector,
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

        vm.stopPrank();*/
    }
}
