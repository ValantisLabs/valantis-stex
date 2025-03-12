// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalModuleKeeper} from "src/owner/WithdrawalModuleKeeper.sol";
import {WithdrawalModuleManager} from "src/owner/WithdrawalModuleManager.sol";

contract WithdrawalModuleKeeperTest is Test {
    WithdrawalModuleKeeper keeper;
    WithdrawalModuleManager manager;

    address public keeperAccount1 = makeAddr("KEEPER_ACCOUNT_1");
    address public keeperAccount2 = makeAddr("KEEPER_ACCOUNT_2");

    function setUp() public {
        keeper = new WithdrawalModuleKeeper(address(this));
        assertEq(keeper.owner(), address(this));

        manager = new WithdrawalModuleManager(address(this), address(keeper));
        assertEq(manager.owner(), address(this));
        assertEq(manager.keeper(), address(keeper));

        keeper.setKeeper(keeperAccount1);
        assertTrue(keeper.isKeeper(keeperAccount1));
        assertFalse(keeper.isKeeper(keeperAccount2));
    }

    /// Withdrawal Module mock functions ///

    /// End of Withdrawal Module mock functions ///

    function testDeployments() public {
        WithdrawalModuleKeeper keeperDeployment = new WithdrawalModuleKeeper(address(this));
        assertEq(keeperDeployment.owner(), address(this));

        vm.expectRevert(WithdrawalModuleManager.WithdrawalModuleManager__ZeroAddress.selector);
        new WithdrawalModuleManager(address(this), address(0));

        WithdrawalModuleManager managerDeployment =
            new WithdrawalModuleManager(address(this), address(keeperDeployment));
        assertEq(managerDeployment.owner(), address(this));
        assertEq(managerDeployment.keeper(), address(keeperDeployment));
    }

    function testKeeperWhitelist() public {
        vm.expectRevert(WithdrawalModuleKeeper.WithdrawalModuleKeeper__ZeroAddress.selector);
        keeper.setKeeper(address(0));

        keeper.setKeeper(keeperAccount2);
        assertTrue(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(WithdrawalModuleKeeper.WithdrawalModuleKeeper__ZeroAddress.selector);
        keeper.removeKeeper(address(0));

        keeper.removeKeeper(keeperAccount2);
        assertFalse(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(WithdrawalModuleManager.WithdrawalModuleManager__ZeroAddress.selector);
        manager.setKeeper(address(0));

        manager.setKeeper(keeperAccount2);
        assertEq(manager.keeper(), keeperAccount2);
    }
}
