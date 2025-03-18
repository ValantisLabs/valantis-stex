// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

        vm.deal(address(this), 10 ether);
    }

    /// Withdrawal Module mock functions ///

    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient) external {}

    function supplyToken1ToLendingPool(uint256 _amountToken1) external {}

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external {}

    function update() external {}

    /// End of Withdrawal Module mock functions ///

    /// Overseer mock functions ///

    function getBurnIds(address _account) external view returns (uint256[] memory) {
        if (_account != address(this)) {
            return new uint256[](0);
        }

        uint256[] memory burnIds = new uint256[](3);

        burnIds[1] = 1;
        burnIds[2] = 2;

        return burnIds;
    }

    function redeemable(uint256 burnId) external pure returns (bool) {
        if (burnId == 1 || burnId > 2) return false;

        return true;
    }

    function redeem(uint256 burnId) external {}

    /// End of Overseer mock functions ///

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

    function testManagerContract__KeeperFunctions() public {
        address withdrawalModule = address(this);

        // Only keeper can call the following functions

        vm.expectRevert(WithdrawalModuleManager.WithdrawalModuleManager__OnlyKeeper.selector);
        manager.unstakeToken0Reserves(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.unstakeToken0Reserves(withdrawalModule, 1 ether);

        vm.expectRevert(WithdrawalModuleManager.WithdrawalModuleManager__OnlyKeeper.selector);
        manager.supplyToken1ToLendingPool(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.supplyToken1ToLendingPool(withdrawalModule, 1 ether);

        vm.expectRevert(WithdrawalModuleManager.WithdrawalModuleManager__OnlyKeeper.selector);
        manager.withdrawToken1FromLendingPool(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.withdrawToken1FromLendingPool(withdrawalModule, 1 ether);

        // Keeper cannot call owner restricted function
        vm.prank(address(keeper));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(keeper)));
        manager.call(withdrawalModule, new bytes(0));
    }

    function testManagerContract__OwnerFunctions() public {
        address withdrawalModule = address(this);

        vm.prank(address(keeper));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(keeper)));
        manager.call(withdrawalModule, new bytes(0));

        // owner can call the same functions as keeper's via `call`,
        // given its increased access privilleges

        manager.call(withdrawalModule, abi.encodeWithSelector(this.unstakeToken0Reserves.selector, 1 ether));

        manager.call(withdrawalModule, abi.encodeWithSelector(this.supplyToken1ToLendingPool.selector, 1 ether));

        manager.call(
            withdrawalModule, abi.encodeWithSelector(this.withdrawToken1FromLendingPool.selector, 1 ether, address(0))
        );
    }

    function testKeeperContract__call() public {
        address withdrawalModule = address(this);

        vm.expectRevert(WithdrawalModuleKeeper.WithdrawalModuleKeeper__call_onlyKeeper.selector);
        vm.prank(keeperAccount2);
        keeper.call(address(manager), new bytes(0));

        vm.startPrank(keeperAccount1);

        // The following functions can be called by a whitelisted keeper role

        keeper.call(
            address(manager),
            abi.encodeWithSelector(WithdrawalModuleManager.unstakeToken0Reserves.selector, withdrawalModule, 1 ether)
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.supplyToken1ToLendingPool.selector, withdrawalModule, 1 ether
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.withdrawToken1FromLendingPool.selector, withdrawalModule, 1 ether
            )
        );

        // `call` from WithdrawalModuleManager cannot be called by keeper contract

        vm.expectRevert(WithdrawalModuleKeeper.WithdrawalModuleKeeper__call_callFailed.selector);
        keeper.call(
            address(manager),
            abi.encodeWithSelector(WithdrawalModuleManager.call.selector, withdrawalModule, new bytes(0))
        );
    }

    function testKeeper__GetOverseerBurnIds() public view {
        address overseer = address(this);

        uint256[] memory burnIds = keeper.getOverseerBurnIds(overseer, address(1));
        assertEq(burnIds.length, 0);

        burnIds = keeper.getOverseerBurnIds(overseer, address(this));
        assertEq(burnIds.length, 3);
    }

    function testKeeper__RedeemBurnIdsAndUpdate() public {
        address overseer = address(this);

        uint256[] memory burnIds = keeper.getOverseerBurnIds(overseer, address(this));
        assertEq(burnIds.length, 3);

        bool[] memory burnIdsProcessed = keeper.redeemBurnsAndUpdate(burnIds, overseer, address(this));
        assertEq(burnIdsProcessed.length, burnIds.length);
        assertTrue(burnIdsProcessed[0]);
        assertFalse(burnIdsProcessed[1]);
        assertTrue(burnIdsProcessed[2]);
    }
}
