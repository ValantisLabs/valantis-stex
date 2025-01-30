// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {WithdrawalModule} from "src/WithdrawalModule.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

contract WithdrawalModuleTest is Test {
    WithdrawalModule withdrawalModule;

    WETH weth;
    MockStHype private _token0;

    MockOverseer overseer;

    address private _pool = makeAddr("MOCK_POOL");

    function setUp() public {
        overseer = new MockOverseer();

        withdrawalModule = new WithdrawalModule(address(overseer), address(this));

        _token0 = new MockStHype();
        weth = new WETH();

        // AMM will be mocked to make testing more flexible
        withdrawalModule.setHAMM(address(this));
        assertEq(withdrawalModule.hamm(), address(this));

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        // Simulates a positive rebase
        vm.deal(address(_token0), 20 ether);
        uint256 shares = _token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(_token0.totalSupply(), shares);
        assertEq(_token0.balanceOf(address(this)), shares);
        assertEq(address(_token0).balance, 120 ether);

        _token0.approve(address(withdrawalModule), type(uint256).max);
    }

    // AMM mock functions

    function token0() external view returns (address) {
        return address(_token0);
    }

    function token1() external view returns (address) {
        return address(weth);
    }

    function pool() external view returns (address) {
        return _pool;
    }

    function unstakeToken0Reserves() external {}

    function testDeploy() public returns (WithdrawalModule withdrawalModuleDeployment) {
        vm.expectRevert(WithdrawalModule.WithdrawalModule__ZeroAddress.selector);
        new WithdrawalModule(address(0), address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new WithdrawalModule(address(overseer), address(0));

        withdrawalModuleDeployment = new WithdrawalModule(address(overseer), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.owner(), address(this));
    }

    function testSetHAMM() public {
        WithdrawalModule withdrawalModuleDeployment = testDeploy();

        vm.prank(_pool);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _pool));
        withdrawalModuleDeployment.setHAMM(address(this));

        vm.expectRevert(WithdrawalModule.WithdrawalModule__ZeroAddress.selector);
        withdrawalModuleDeployment.setHAMM(address(0));

        withdrawalModuleDeployment.setHAMM(address(this));
        assertEq(withdrawalModuleDeployment.hamm(), address(this));

        vm.expectRevert(WithdrawalModule.WithdrawalModule__setHAMM_AlreadySet.selector);
        withdrawalModuleDeployment.setHAMM(_pool);
    }

    function testReceive() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(withdrawalModule).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(withdrawalModule).balance, 1 ether);
    }

    function testBurnToken0AfterWithdraw() public {
        uint256 amountToken0 = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");

        vm.prank(_pool);
        vm.expectRevert(WithdrawalModule.WithdrawalModule__OnlyHAMM.selector);
        withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);

        withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);
        // No token0 has been unstaked
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), withdrawalModule.convertToToken1(amountToken0));
        (address to, uint96 amount, uint256 amountCumulative) = withdrawalModule.LPWithdrawals(0);
        assertEq(to, recipient);
        assertEq(amount, withdrawalModule.convertToToken1(amountToken0));
        assertEq(amountCumulative, 0);
        assertEq(withdrawalModule.idLPWithdrawal(), 1);
    }

    function testUnstakeToken0Reserves() public {
        vm.prank(_pool);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _pool));
        withdrawalModule.unstakeToken0Reserves();

        _token0.transfer(address(withdrawalModule), 3 ether);
        withdrawalModule.unstakeToken0Reserves();
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether);
    }

    function testUpdate() public {
        // No state updates have happened
        withdrawalModule.update();
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        testUnstakeToken0Reserves();
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether);

        uint256 snapshot = vm.snapshot();
        uint256 snapshot2 = vm.snapshot();

        // Update with partial unstaking fulfilled
        vm.deal(address(withdrawalModule), 2 ether);
        withdrawalModule.update();

        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether - withdrawalModule.convertToToken0(2 ether));
        // All ETH got wrapped and transferred into pool,
        // since there were no LP withdrawals to fulfill
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(_pool), 2 ether);

        vm.revertTo(snapshot2);

        // Update with partial unstaking fulfilled and partial LP withdrawal

        address recipient = makeAddr("MOCK_RECIPIENT");
        withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);
        uint256 amountToken1PendingLPWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(amountToken1PendingLPWithdrawal, withdrawalModule.convertToToken1(1 ether));

        vm.deal(address(withdrawalModule), 0.5 ether);
        withdrawalModule.update();

        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether - withdrawalModule.convertToToken0(0.5 ether));
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0.5 ether);
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), amountToken1PendingLPWithdrawal - 0.5 ether);
        assertEq(address(withdrawalModule).balance, 0.5 ether);
        // Not enough ETH left to re-deposit into pool
        assertEq(weth.balanceOf(_pool), 0);

        // Cannot claim withdrawal request because there is not enough ETH available
        vm.expectRevert(WithdrawalModule.WithdrawalModule__claim_insufficientAmountToClaim.selector);
        withdrawalModule.claim(0);

        vm.revertTo(snapshot);

        recipient = makeAddr("MOCK_RECIPIENT");
        withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);
        amountToken1PendingLPWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(amountToken1PendingLPWithdrawal, withdrawalModule.convertToToken1(1 ether));

        vm.deal(address(withdrawalModule), 5 ether);
        withdrawalModule.update();

        // All unstaking requests got fulfilled
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        // Pending LP withdrawal can now be claimed
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), amountToken1PendingLPWithdrawal);
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(address(withdrawalModule).balance, amountToken1PendingLPWithdrawal);
        // Remaining ETH amount got wrapped and re-deposited into pool
        assertEq(weth.balanceOf(_pool), 5 ether - amountToken1PendingLPWithdrawal);

        withdrawalModule.claim(0);
        assertEq(recipient.balance, amountToken1PendingLPWithdrawal);
    }
}
