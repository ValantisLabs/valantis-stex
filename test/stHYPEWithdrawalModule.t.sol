// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

contract stHYPEWithdrawalModuleTest is Test {
    stHYPEWithdrawalModule withdrawalModule;

    WETH weth;
    MockStHype private _token0;

    MockOverseer overseer;

    MockLendingPool lendingPool;

    address private _pool = makeAddr("MOCK_POOL");

    address public owner = makeAddr("OWNER");

    function setUp() public {
        overseer = new MockOverseer();

        _token0 = new MockStHype();
        weth = new WETH();

        lendingPool = new MockLendingPool(address(weth));
        assertEq(lendingPool.underlyingAsset(), address(weth));
        assertEq(lendingPool.lendingPoolYieldToken(), address(lendingPool));

        withdrawalModule = new stHYPEWithdrawalModule(
            address(overseer), address(lendingPool), lendingPool.lendingPoolYieldToken(), owner
        );
        assertEq(withdrawalModule.lendingPool(), address(lendingPool));
        assertEq(withdrawalModule.lendingPoolYieldToken(), address(lendingPool));
        assertEq(withdrawalModule.owner(), owner);

        vm.startPrank(owner);
        // AMM will be mocked to make testing more flexible
        withdrawalModule.setSTEX(address(this));
        assertEq(withdrawalModule.stex(), address(this));
        vm.stopPrank();

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

    function supplyToken1Reserves(uint256 amount) external {
        weth.transfer(msg.sender, amount);
    }

    function testDeploy() public returns (stHYPEWithdrawalModule withdrawalModuleDeployment) {
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__ZeroAddress.selector);
        new stHYPEWithdrawalModule(address(0), address(0), address(0), address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new stHYPEWithdrawalModule(address(overseer), address(0), address(0), address(0));

        // If lendingPool is specified, lendingPoolYieldToken cannot be zero address
        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__constructor_InvalidLendingPoolYieldToken.selector
        );
        new stHYPEWithdrawalModule(address(overseer), address(lendingPool), address(0), address(this));

        withdrawalModuleDeployment =
            new stHYPEWithdrawalModule(address(overseer), address(0), address(0), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.owner(), address(this));
    }

    function testAmountToken1LendingPool() public {
        vm.startPrank(owner);

        uint256 balance = withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 0);

        withdrawalModule.supplyToken1ToLendingPool(2 ether);

        balance = withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 2 ether);

        vm.stopPrank();

        // simulate rebase
        weth.transfer(address(lendingPool), 0.1 ether);
        balance = withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 2.1 ether);
    }

    function testSetSTEX() public {
        stHYPEWithdrawalModule withdrawalModuleDeployment = testDeploy();

        vm.prank(_pool);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _pool));
        withdrawalModuleDeployment.setSTEX(address(this));

        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__ZeroAddress.selector);
        withdrawalModuleDeployment.setSTEX(address(0));

        withdrawalModuleDeployment.setSTEX(address(this));
        assertEq(withdrawalModuleDeployment.stex(), address(this));

        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__setSTEX_AlreadySet.selector);
        withdrawalModuleDeployment.setSTEX(_pool);
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

        _burnToken0AfterWithdraw(amountToken0, recipient);
    }

    function testUnstakeToken0Reserves() public {
        _unstakeToken0Reserves(3 ether);
    }

    function testWithdrawToken1FromLendingPool() public {
        uint256 amountToken1 = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");

        vm.prank(recipient);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__OnlySTEXOrOwner.selector);
        withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);

        vm.startPrank(owner);

        // Owner transfers liquidity from lending pool to sovereign pool
        withdrawalModule.supplyToken1ToLendingPool(2 * amountToken1);

        withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(_pool), amountToken1);
        assertEq(weth.balanceOf(recipient), 0);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        // AMM transfers liquidity from lending pool to recipient
        withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(recipient), amountToken1);

        vm.revertTo(snapshot);

        // Revert happens if recipient receives less than amountToken1
        lendingPool.setIsCompromised(true);

        vm.expectRevert(
            stHYPEWithdrawalModule
                .stHYPEWithdrawalModule__withdrawToken1FromLendingPool_insufficientAmountWithdrawn
                .selector
        );
        withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
    }

    function testUpdate() public {
        // No state updates have happened
        withdrawalModule.update();
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        _unstakeToken0Reserves(3 ether);
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether);

        uint256 snapshot = vm.snapshotState();
        uint256 snapshot2 = vm.snapshotState();

        // Update with partial unstaking fulfilled
        vm.deal(address(withdrawalModule), 2 ether);
        withdrawalModule.update();

        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 3 ether - withdrawalModule.convertToToken0(2 ether));
        // All ETH got wrapped and transferred into pool,
        // since there were no LP withdrawals to fulfill
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(_pool), 2 ether);

        vm.revertToState(snapshot2);

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
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_insufficientAmountToClaim.selector);
        withdrawalModule.claim(0);

        vm.revertToState(snapshot);

        // Update with all unstaking requests and LP withdrawals fulfilled + remaining funds re-deposited into pool

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

    function testClaimWithPriority() public {
        uint256 amount1 = 1 ether;
        address recipient1 = makeAddr("MOCK_RECIPIENT_1");
        // User 1 requests withdrawal (before unstaking fulfillment)
        _burnToken0AfterWithdraw(amount1, recipient1);

        // User 2 requests withdrawal (before unstaking fulfillment)
        uint256 amount2 = 2 ether;
        address recipient2 = makeAddr("MOCK_RECIPIENT_2");
        _burnToken0AfterWithdraw(amount2, recipient2);

        // Simulate unstaking fulfillment
        vm.deal(address(withdrawalModule), 4 ether);
        withdrawalModule.update();

        // User 3 requests withdrawal (after unstaking fulfillment)
        uint256 amount3 = 0.1 ether;
        address recipient3 = makeAddr("MOCK_RECIPIENT_3");
        _burnToken0AfterWithdraw(amount3, recipient3);

        // User 1 can claim, because it requested withdrawal before the call to `update`
        withdrawalModule.claim(0);
        assertGt(recipient1.balance, 0);

        // User 3 cannot claim, because it requested withdrawal after the call to `update`
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_cannotYetClaim.selector);
        withdrawalModule.claim(2);

        // User 2 can claim, similar scenario to user 1
        withdrawalModule.claim(1);
        assertGt(recipient2.balance, 0);
    }

    function _burnToken0AfterWithdraw(uint256 amountToken0, address recipient) private {
        vm.prank(_pool);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__OnlySTEX.selector);
        withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);

        uint256 preAmountToken0PendingUnstaking = withdrawalModule.amountToken0PendingUnstaking();
        uint256 preAmountToken1PendingLPWithdrawal = withdrawalModule.amountToken1PendingLPWithdrawal();
        withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);
        // No token0 has been unstaked
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), preAmountToken0PendingUnstaking);
        assertEq(
            withdrawalModule.amountToken1PendingLPWithdrawal(),
            withdrawalModule.convertToToken1(amountToken0) + preAmountToken1PendingLPWithdrawal
        );
        uint256 preId = withdrawalModule.idLPWithdrawal() - 1;
        uint256 preAmountCumulative = withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal();
        (address to, uint96 amount, uint256 amountCumulative) = withdrawalModule.LPWithdrawals(preId);
        assertEq(to, recipient);
        assertEq(amount, withdrawalModule.convertToToken1(amountToken0));
        assertEq(amountCumulative, preAmountCumulative);
    }

    function _unstakeToken0Reserves(uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        withdrawalModule.unstakeToken0Reserves();

        uint256 preAmountToken0PendingUnstaking = withdrawalModule.amountToken0PendingUnstaking();
        _token0.transfer(address(withdrawalModule), amount);

        vm.startPrank(owner);
        withdrawalModule.unstakeToken0Reserves();
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), preAmountToken0PendingUnstaking + amount);

        vm.stopPrank();
    }
}
