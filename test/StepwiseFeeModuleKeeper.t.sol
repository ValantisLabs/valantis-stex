// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {StepwiseFeeModuleKeeper} from "src/owner/StepwiseFeeModuleKeeper.sol";

contract StepwiseFeeModuleKeeperTest is Test {
    StepwiseFeeModuleKeeper keeper;

    address public keeperAccount1 = makeAddr("KEEPER_ACCOUNT_1");
    address public keeperAccount2 = makeAddr("KEEPER_ACCOUNT_2");

    function setUp() public {
        keeper = new StepwiseFeeModuleKeeper(address(this));
        assertEq(keeper.owner(), address(this));

        keeper.setKeeper(keeperAccount1);
        assertTrue(keeper.isKeeper(keeperAccount1));
        assertFalse(keeper.isKeeper(keeperAccount2));
    }

    /// Stepwise Fee Module mock functions ///

    function setFeeParamsToken0(
        uint256 _minThresholdToken1,
        uint256 _maxThresholdToken1,
        uint32[] calldata _feeStepsInBips
    ) external {}

    /// End of Stepwise Fee Module mock functions ///

    function testDeployments() public {
        StepwiseFeeModuleKeeper keeperDeployment = new StepwiseFeeModuleKeeper(address(this));
        assertEq(keeperDeployment.owner(), address(this));
    }

    function testKeeperWhitelist() public {
        vm.expectRevert(StepwiseFeeModuleKeeper.StepwiseFeeModuleKeeper__ZeroAddress.selector);
        keeper.setKeeper(address(0));

        keeper.setKeeper(keeperAccount2);
        assertTrue(keeper.isKeeper(keeperAccount2));

        vm.expectRevert(StepwiseFeeModuleKeeper.StepwiseFeeModuleKeeper__ZeroAddress.selector);
        keeper.removeKeeper(address(0));

        keeper.removeKeeper(keeperAccount2);
        assertFalse(keeper.isKeeper(keeperAccount2));
    }

    function test_setToken0FeeParams() public {
        uint32[] memory feeStepsInBipsToken0 = new uint32[](3);
        feeStepsInBipsToken0[0] = 1;
        feeStepsInBipsToken0[1] = 2;
        feeStepsInBipsToken0[2] = 3;

        vm.expectRevert(StepwiseFeeModuleKeeper.StepwiseFeeModuleKeeper__setFeeParamsToken0_OnlyKeeper.selector);
        keeper.setFeeParamsToken0(address(0), 10 ether, 100 ether, feeStepsInBipsToken0);

        vm.startPrank(keeperAccount1);

        vm.expectRevert(StepwiseFeeModuleKeeper.StepwiseFeeModuleKeeper__ZeroAddress.selector);
        keeper.setFeeParamsToken0(address(0), 10 ether, 100 ether, feeStepsInBipsToken0);

        keeper.setFeeParamsToken0(address(this), 10 ether, 100 ether, feeStepsInBipsToken0);

        vm.stopPrank();
    }

    /*function testKeeperContract__call() public {
        address withdrawalModule = address(this);

        vm.expectRevert(
            WithdrawalModuleKeeper
                .WithdrawalModuleKeeper__call_onlyKeeper
                .selector
        );
        vm.prank(keeperAccount2);
        keeper.call(address(manager), new bytes(0));

        vm.startPrank(keeperAccount1);

        // The following functions can be called by a whitelisted keeper role

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.unstakeToken0Reserves.selector,
                withdrawalModule,
                1 ether
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.supplyToken1ToLendingPool.selector,
                withdrawalModule,
                1 ether
            )
        );

        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.withdrawToken1FromLendingPool.selector,
                withdrawalModule,
                1 ether
            )
        );

        // `call` from WithdrawalModuleManager cannot be called by keeper contract

        vm.expectRevert(
            WithdrawalModuleKeeper
                .WithdrawalModuleKeeper__call_callFailed
                .selector
        );
        keeper.call(
            address(manager),
            abi.encodeWithSelector(
                WithdrawalModuleManager.call.selector,
                withdrawalModule,
                new bytes(0)
            )
        );
    }*/
}
