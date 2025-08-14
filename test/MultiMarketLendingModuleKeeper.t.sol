// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MultiMarketLendingModuleKeeper} from "src/owner/MultiMarketLendingModuleKeeper.sol";
import {MultiMarketLendingModuleManager} from "src/owner/MultiMarketLendingModuleManager.sol";

contract MultiMarketLendingModuleKeeperTest is Test {
    MultiMarketLendingModuleKeeper keeper;
    MultiMarketLendingModuleManager manager;

    address public keeperAccount1 = makeAddr("KEEPER_ACCOUNT_1");
    address public keeperAccount2 = makeAddr("KEEPER_ACCOUNT_2");

    function setUp() public {
        keeper = new MultiMarketLendingModuleKeeper(address(this));
        assertEq(keeper.owner(), address(this));

        manager = new MultiMarketLendingModuleManager(address(this), address(keeper));
        assertEq(manager.owner(), address(this));
        assertEq(manager.keeper(), address(keeper));

        keeper.setKeeper(keeperAccount1);
        assertTrue(keeper.isKeeper(keeperAccount1));
        assertFalse(keeper.isKeeper(keeperAccount2));
    }

    /// MultiMarketLendingModule mock functions ///

    function acceptOwnership() external {}

    function setDepositWeights(uint16[] memory _depositWeightBipsArray) external {}

    function setWithdrawWeights(uint16[] memory _withdrawWeightBipsArray) external {}

    function claimManagerFee(address _recipient) external {}

    /// End of MultiMarketLendingModule mock functions ///

    function testDeployments() public {
        vm.expectRevert();
        new MultiMarketLendingModuleKeeper(address(0));

        MultiMarketLendingModuleKeeper keeperDeployment = new MultiMarketLendingModuleKeeper(address(this));
        assertEq(keeperDeployment.owner(), address(this));

        vm.expectRevert();
        new MultiMarketLendingModuleManager(address(0), address(keeperDeployment));

        vm.expectRevert(MultiMarketLendingModuleManager.MultiMarketLendingModuleManager__ZeroAddress.selector);
        new MultiMarketLendingModuleManager(address(this), address(0));

        MultiMarketLendingModuleManager managerDeployment =
            new MultiMarketLendingModuleManager(address(this), address(keeperDeployment));
        assertEq(managerDeployment.owner(), address(this));
        assertEq(managerDeployment.keeper(), address(keeperDeployment));
    }

    function testKeeperWhitelist() public {
        vm.expectRevert(MultiMarketLendingModuleKeeper.MultiMarketLendingModuleKeeper__ZeroAddress.selector);
        keeper.setKeeper(address(0));

        keeper.setKeeper(keeperAccount2);
        assertTrue(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(MultiMarketLendingModuleKeeper.MultiMarketLendingModuleKeeper__ZeroAddress.selector);
        keeper.removeKeeper(address(0));

        keeper.removeKeeper(keeperAccount2);
        assertFalse(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(MultiMarketLendingModuleManager.MultiMarketLendingModuleManager__ZeroAddress.selector);
        manager.setKeeper(address(0));

        manager.setKeeper(keeperAccount2);
        assertEq(manager.keeper(), keeperAccount2);
    }

    function testManagerContract__KeeperFunctions() public {
        address lendingModule = address(this);

        // Only keeper can call the following functions

        vm.expectRevert(MultiMarketLendingModuleManager.MultiMarketLendingModuleManager__OnlyKeeper.selector);
        manager.setDepositWeights(lendingModule, new uint16[](0));

        vm.prank(address(keeper));
        manager.setDepositWeights(lendingModule, new uint16[](0));

        vm.expectRevert(MultiMarketLendingModuleManager.MultiMarketLendingModuleManager__OnlyKeeper.selector);
        manager.setWithdrawWeights(lendingModule, new uint16[](0));

        vm.prank(address(keeper));
        manager.setWithdrawWeights(lendingModule, new uint16[](0));

        vm.expectRevert(MultiMarketLendingModuleManager.MultiMarketLendingModuleManager__OnlyKeeper.selector);
        manager.claimManagerFee(lendingModule, address(this));

        vm.prank(address(keeper));
        manager.claimManagerFee(lendingModule, address(this));

        // Keeper cannot call owner restricted function
        vm.prank(address(keeper));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(keeper)));
        manager.call(lendingModule, new bytes(0));
    }

    function testManagerContract__OwnerFunctions() public {
        address lendingModule = address(this);

        vm.prank(address(keeper));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(keeper)));
        manager.call(lendingModule, new bytes(0));

        manager.acceptOwnership(lendingModule);

        // owner can call the same functions as keeper's via `call`,
        // given its increased access privilleges

        manager.call(lendingModule, abi.encodeWithSelector(this.setDepositWeights.selector, new uint16[](0)));

        manager.call(lendingModule, abi.encodeWithSelector(this.setWithdrawWeights.selector, new uint16[](0)));

        manager.call(lendingModule, abi.encodeWithSelector(this.claimManagerFee.selector, address(this)));
    }

    function testKeeperContract__call() public {
        address lendingModule = address(this);

        vm.expectRevert(MultiMarketLendingModuleKeeper.MultiMarketLendingModuleKeeper__call_onlyKeeper.selector);
        vm.prank(keeperAccount2);
        keeper.call(address(manager), new bytes(0));

        vm.startPrank(keeperAccount1);

        // The following functions can be called by a whitelisted keeper role

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                MultiMarketLendingModuleManager.setDepositWeights.selector, lendingModule, new uint16[](0)
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                MultiMarketLendingModuleManager.setWithdrawWeights.selector, lendingModule, new uint16[](0)
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                MultiMarketLendingModuleManager.claimManagerFee.selector, lendingModule, address(this)
            )
        );

        // `call` from WithdrawalModuleManager cannot be called by keeper contract

        vm.expectRevert(MultiMarketLendingModuleKeeper.MultiMarketLendingModuleKeeper__call_callFailed.selector);
        keeper.call(
            address(manager),
            abi.encodeWithSelector(MultiMarketLendingModuleManager.call.selector, lendingModule, new bytes(0))
        );
    }
}
