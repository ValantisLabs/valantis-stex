// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {kHYPEWithdrawalModuleKeeper} from "src/owner/kHYPEWithdrawalModuleKeeper.sol";
import {kHYPEWithdrawalModuleManager} from "src/owner/kHYPEWithdrawalModuleManager.sol";
import {IRebalanceModule} from "src/interfaces/IRebalanceModule.sol";

contract kHYPEWithdrawalModuleKeeperTest is Test {
    kHYPEWithdrawalModuleKeeper keeper;
    kHYPEWithdrawalModuleManager manager;

    address public keeperAccount1 = makeAddr("KEEPER_ACCOUNT_1");
    address public keeperAccount2 = makeAddr("KEEPER_ACCOUNT_2");

    function setUp() public {
        keeper = new kHYPEWithdrawalModuleKeeper(address(this));
        assertEq(keeper.owner(), address(this));

        manager = new kHYPEWithdrawalModuleManager(address(this), address(keeper));
        assertEq(manager.owner(), address(this));
        assertEq(manager.keeper(), address(keeper));

        keeper.setKeeper(keeperAccount1);
        assertTrue(keeper.isKeeper(keeperAccount1));
        assertFalse(keeper.isKeeper(keeperAccount2));

        vm.deal(address(this), 10 ether);
    }

    /// Withdrawal Module mock functions ///

    function stakeToken1(uint256 _amountToken1) external {}

    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient) external {}

    function supplyToken1ToLendingPool(uint256 _amountToken1) external {}

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external {}

    function rebalanceToken0Reserves(
        uint256 _amountToken0,
        address _recipient,
        address _rebalanceModule,
        bytes calldata _payload
    ) external {}

    function unstakeExcessToken0() external {}

    function settlePendingWithdrawalsWithPoolReserves(uint256 _amountToken1) external {}

    function update() external {}

    function confirmWithdrawal(uint256 _id) external returns (bool isConfirmed) {}

    /// End of Withdrawal Module mock functions ///

    /// Rebalance Module mock functions ///

    function rebalance(
        uint256,
        /*amountToken1Min*/
        bytes calldata /*_data*/
    )
        external
        pure
        returns (bytes4)
    {
        return IRebalanceModule.rebalance.selector;
    }

    /// End of Rebalance Module mock functions ///

    function testDeployments() public {
        kHYPEWithdrawalModuleKeeper keeperDeployment = new kHYPEWithdrawalModuleKeeper(address(this));
        assertEq(keeperDeployment.owner(), address(this));

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__ZeroAddress.selector);
        new kHYPEWithdrawalModuleManager(address(this), address(0));

        kHYPEWithdrawalModuleManager managerDeployment =
            new kHYPEWithdrawalModuleManager(address(this), address(keeperDeployment));
        assertEq(managerDeployment.owner(), address(this));
        assertEq(managerDeployment.keeper(), address(keeperDeployment));
    }

    function testKeeperWhitelist() public {
        vm.expectRevert(kHYPEWithdrawalModuleKeeper.kHYPEWithdrawalModuleKeeper__ZeroAddress.selector);
        keeper.setKeeper(address(0));

        keeper.setKeeper(keeperAccount2);
        assertTrue(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(kHYPEWithdrawalModuleKeeper.kHYPEWithdrawalModuleKeeper__ZeroAddress.selector);
        keeper.removeKeeper(address(0));

        keeper.removeKeeper(keeperAccount2);
        assertFalse(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__ZeroAddress.selector);
        manager.setKeeper(address(0));

        manager.setKeeper(keeperAccount2);
        assertEq(manager.keeper(), keeperAccount2);
    }

    function testManagerContract__KeeperFunctions() public {
        address withdrawalModule = address(this);

        // Only keeper can call the following functions

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.stakeToken1(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.stakeToken1(withdrawalModule, 1 ether);

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.unstakeToken0Reserves(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.unstakeToken0Reserves(withdrawalModule, 1 ether);

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.supplyToken1ToLendingPool(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.supplyToken1ToLendingPool(withdrawalModule, 1 ether);

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.withdrawToken1FromLendingPool(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.withdrawToken1FromLendingPool(withdrawalModule, 1 ether);

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.settlePendingWithdrawalsWithPoolReserves(withdrawalModule, 1 ether);

        vm.prank(address(keeper));
        manager.settlePendingWithdrawalsWithPoolReserves(withdrawalModule, 1 ether);

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.rebalanceToken0Reserves(withdrawalModule, 1 ether, address(this), address(this), new bytes(0));

        vm.prank(address(keeper));
        manager.rebalanceToken0Reserves(withdrawalModule, 1 ether, address(this), address(this), new bytes(0));

        vm.expectRevert(kHYPEWithdrawalModuleManager.kHYPEWithdrawalModuleManager__OnlyKeeper.selector);
        manager.unstakeExcessToken0(withdrawalModule);

        vm.prank(address(keeper));
        manager.unstakeExcessToken0(withdrawalModule);

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

        vm.expectRevert(kHYPEWithdrawalModuleKeeper.kHYPEWithdrawalModuleKeeper__call_onlyKeeper.selector);
        vm.prank(keeperAccount2);
        keeper.call(address(manager), new bytes(0));

        vm.startPrank(keeperAccount1);

        // The following functions can be called by a whitelisted keeper role

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                kHYPEWithdrawalModuleManager.unstakeToken0Reserves.selector, withdrawalModule, 1 ether
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                kHYPEWithdrawalModuleManager.supplyToken1ToLendingPool.selector, withdrawalModule, 1 ether
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                kHYPEWithdrawalModuleManager.withdrawToken1FromLendingPool.selector, withdrawalModule, 1 ether
            )
        );

        // `call` from WithdrawalModuleManager cannot be called by keeper contract

        vm.expectRevert(kHYPEWithdrawalModuleKeeper.kHYPEWithdrawalModuleKeeper__call_callFailed.selector);
        keeper.call(
            address(manager),
            abi.encodeWithSelector(kHYPEWithdrawalModuleManager.call.selector, withdrawalModule, new bytes(0))
        );
    }

    function testKeeperContract__redeemBurnsAndUpdate() public {
        address withdrawalModule = address(this);

        uint256[] memory burnIds = new uint256[](2);
        burnIds[0] = 2;
        burnIds[1] = 12;

        keeper.redeemBurnsAndUpdate(burnIds, withdrawalModule);
    }
}
