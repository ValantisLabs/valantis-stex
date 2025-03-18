// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";
import {AaveLendingModule} from "src/AaveLendingModule.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {STEXLens} from "src/STEXLens.sol";

contract MockPool {
    bool private _isLocked = false;

    function isLocked() external view returns (bool) {
        return _isLocked;
    }

    function setIsLocked(bool _value) external {
        _isLocked = _value;
    }
}

contract stHYPEWithdrawalModuleTest is Test {
    STEXLens stexLens;

    stHYPEWithdrawalModule _withdrawalModule;

    WETH weth;
    MockStHype private _token0;

    MockOverseer overseer;

    MockLendingPool lendingPool;
    AaveLendingModule lendingModule;

    address private _pool;

    address public owner = makeAddr("OWNER");

    function setUp() public {
        stexLens = new STEXLens();

        overseer = new MockOverseer();

        _token0 = new MockStHype();
        weth = new WETH();

        _pool = address(new MockPool());

        lendingPool = new MockLendingPool(address(weth));
        assertEq(lendingPool.underlyingAsset(), address(weth));
        assertEq(lendingPool.lendingPoolYieldToken(), address(lendingPool));

        _withdrawalModule = new stHYPEWithdrawalModule(address(overseer), owner);

        vm.startPrank(owner);
        // AMM will be mocked to make testing more flexible
        _withdrawalModule.setSTEX(address(this));
        assertEq(_withdrawalModule.stex(), address(this));
        vm.stopPrank();

        lendingModule = new AaveLendingModule(
            address(lendingPool), lendingPool.lendingPoolYieldToken(), address(weth), address(_withdrawalModule)
        );

        vm.startPrank(owner);
        _withdrawalModule.proposeLendingModule(address(lendingModule), 3 days);
        vm.warp(block.timestamp + 3 days);
        _withdrawalModule.setProposedLendingModule();
        vm.stopPrank();

        assertEq(address(_withdrawalModule.lendingModule()), address(lendingModule));
        assertEq(_withdrawalModule.owner(), owner);

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        uint256 shares = _token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(_token0.totalSupply(), shares);
        assertEq(_token0.balanceOf(address(this)), shares);
        assertEq(address(_token0).balance, 100 ether);

        _token0.approve(address(_withdrawalModule), 100 ether);
    }

    // AMM mock functions //

    function withdrawalModule() external view returns (address) {
        return address(_withdrawalModule);
    }

    function token0() external view returns (address) {
        return address(_token0);
    }

    function token1() external view returns (address) {
        return address(weth);
    }

    function pool() external view returns (address) {
        return _pool;
    }

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external {}

    function supplyToken1Reserves(uint256 amount) external {
        weth.transfer(msg.sender, amount);
    }

    // End of AMM mock functions //

    function testDeploy() public returns (stHYPEWithdrawalModule withdrawalModuleDeployment) {
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__ZeroAddress.selector);
        new stHYPEWithdrawalModule(address(0), address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new stHYPEWithdrawalModule(address(overseer), address(0));

        withdrawalModuleDeployment = new stHYPEWithdrawalModule(address(overseer), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.owner(), address(this));
        assertEq(address(withdrawalModuleDeployment.lendingModule()), address(0));
        assertEq(withdrawalModuleDeployment.amountToken1LendingPool(), 0);
    }

    function testToken0Conversion() public {
        address recipient = makeAddr("MOCK_RECIPIENT");
        uint256 amount0 = 1.1 ether;
        uint256 amount1 = _withdrawalModule.convertToToken1(amount0);
        // token0 is rebase
        assertEq(amount0, amount1);
        assertEq(amount0, _withdrawalModule.convertToToken0(amount1));

        uint256 shares = _withdrawalModule.token0BalanceToShares(amount0);
        _token0.transfer(recipient, amount0);

        assertEq(_withdrawalModule.token0SharesOf(recipient), shares);
        assertEq(_withdrawalModule.token0SharesToBalance(shares), amount0);
    }

    function testAmountToken1LendingPool() public {
        vm.startPrank(owner);

        uint256 balance = _withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 0);

        _withdrawalModule.supplyToken1ToLendingPool(2 ether);

        balance = _withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 2 ether);

        vm.stopPrank();

        // simulate rebase
        weth.transfer(address(lendingPool), 0.1 ether);
        balance = _withdrawalModule.amountToken1LendingPool();
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
        (bool success,) = address(_withdrawalModule).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(_withdrawalModule).balance, 1 ether);
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
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);

        vm.startPrank(owner);

        // Owner transfers liquidity from lending pool to sovereign pool
        _withdrawalModule.supplyToken1ToLendingPool(2 * amountToken1);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        MockPool(_pool).setIsLocked(false);

        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(_pool), amountToken1);
        assertEq(weth.balanceOf(recipient), 0);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        // AMM transfers liquidity from lending pool to recipient
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(recipient), amountToken1);

        vm.revertToState(snapshot);

        // Revert happens if recipient receives less than amountToken1
        lendingPool.setIsCompromised(true);

        vm.expectRevert(
            stHYPEWithdrawalModule
                .stHYPEWithdrawalModule__withdrawToken1FromLendingPool_insufficientAmountWithdrawn
                .selector
        );
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
    }

    function testUpdate() public {
        // No state updates have happened
        _withdrawalModule.update();
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.update();
        MockPool(_pool).setIsLocked(false);

        _unstakeToken0Reserves(3 ether);
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 3 ether);

        uint256 snapshot = vm.snapshotState();
        uint256 snapshot2 = vm.snapshotState();

        // Update with partial unstaking fulfilled
        vm.deal(address(_withdrawalModule), 2 ether);
        _withdrawalModule.update();

        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 3 ether - _withdrawalModule.convertToToken0(2 ether));
        // All ETH got wrapped and transferred into pool,
        // since there were no LP withdrawals to fulfill
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(_pool), 2 ether);

        vm.revertToState(snapshot2);

        // Update with partial unstaking fulfilled and partial LP withdrawal

        address recipient = makeAddr("MOCK_RECIPIENT");
        _withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);
        uint256 amountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(amountToken1PendingLPWithdrawal, _withdrawalModule.convertToToken1(1 ether));

        vm.deal(address(_withdrawalModule), 0.5 ether);
        _withdrawalModule.update();

        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(), 3 ether - _withdrawalModule.convertToToken0(0.5 ether)
        );
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0.5 ether);
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), amountToken1PendingLPWithdrawal - 0.5 ether);
        assertEq(address(_withdrawalModule).balance, 0.5 ether);
        // Not enough ETH left to re-deposit into pool
        assertEq(weth.balanceOf(_pool), 0);

        // Cannot claim withdrawal request because there is not enough ETH available
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_insufficientAmountToClaim.selector);
        _withdrawalModule.claim(0);

        vm.revertToState(snapshot);

        // Update with all unstaking requests and LP withdrawals fulfilled + remaining funds re-deposited into pool

        recipient = makeAddr("MOCK_RECIPIENT");
        _withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);
        amountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(amountToken1PendingLPWithdrawal, _withdrawalModule.convertToToken1(1 ether));

        vm.deal(address(_withdrawalModule), 5 ether);
        _withdrawalModule.update();

        // All unstaking requests got fulfilled
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        // Pending LP withdrawal can now be claimed
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), amountToken1PendingLPWithdrawal);
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(address(_withdrawalModule).balance, amountToken1PendingLPWithdrawal);
        // Remaining ETH amount got wrapped and re-deposited into pool
        assertEq(weth.balanceOf(_pool), 5 ether - amountToken1PendingLPWithdrawal);

        _withdrawalModule.claim(0);
        assertEq(recipient.balance, amountToken1PendingLPWithdrawal);
    }

    function testClaimWithPriority() public {
        uint256 amount1 = 1 ether;
        address recipient1 = makeAddr("MOCK_RECIPIENT_1");
        // User 1 requests withdrawal (before unstaking fulfillment)
        _burnToken0AfterWithdraw(amount1, recipient1);
        LPWithdrawalRequest memory request1 = _withdrawalModule.getLPWithdrawals(0);
        assertEq(request1.recipient, recipient1);
        assertEq(request1.amountToken1, amount1);
        assertEq(request1.cumulativeAmountToken1LPWithdrawalCheckpoint, 0);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), amount1);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // User 2 requests withdrawal (before unstaking fulfillment)
        uint256 amount2 = 2 ether;
        address recipient2 = makeAddr("MOCK_RECIPIENT_2");
        _burnToken0AfterWithdraw(amount2, recipient2);
        LPWithdrawalRequest memory request2 = _withdrawalModule.getLPWithdrawals(1);
        assertEq(request2.recipient, recipient2);
        assertEq(request2.amountToken1, amount2);
        assertEq(request2.cumulativeAmountToken1LPWithdrawalCheckpoint, amount1);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), amount1 + amount2);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // Simulate unstaking fulfillment
        vm.deal(address(_withdrawalModule), 4 ether);
        _withdrawalModule.update();
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), amount1 + amount2);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), amount1 + amount2);

        // 1 surplus WETH was transferred to pool
        assertEq(weth.balanceOf(address(_pool)), 1 ether);

        // User 3 requests withdrawal (after unstaking fulfillment)
        uint256 amount3 = 0.1 ether;
        address recipient3 = makeAddr("MOCK_RECIPIENT_3");
        _burnToken0AfterWithdraw(amount3, recipient3);
        LPWithdrawalRequest memory request3 = _withdrawalModule.getLPWithdrawals(2);
        assertEq(request3.recipient, recipient3);
        assertEq(request3.amountToken1, amount3);
        assertEq(request3.cumulativeAmountToken1LPWithdrawalCheckpoint, 3 ether);

        // User 1 can claim, because it requested withdrawal before the call to `update`
        assertTrue(stexLens.canClaim(address(this), 0));
        _withdrawalModule.claim(0);
        assertEq(recipient1.balance, 1 ether);

        // User 3 cannot claim, because it requested withdrawal after the call to `update`
        assertFalse(stexLens.canClaim(address(this), 2));
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_cannotYetClaim.selector);
        _withdrawalModule.claim(2);

        // User 2 can claim, similar scenario to user 1
        assertTrue(stexLens.canClaim(address(this), 1));
        _withdrawalModule.claim(1);
        assertEq(recipient2.balance, 2 ether);

        // User 3 still cannot claim, also because there is not enough ETH
        assertFalse(stexLens.canClaim(address(this), 2));

        // Simulate unstaking fulfillment
        vm.deal(address(_withdrawalModule), 0.1 ether);
        _withdrawalModule.update();

        // User 3 can now claim
        assertTrue(stexLens.canClaim(address(this), 2));
        _withdrawalModule.claim(2);
        assertEq(recipient3.balance, 0.1 ether);

        // User 3 already claimed
        assertFalse(stexLens.canClaim(address(this), 2));
    }

    function testClaimWithPriority__LaterWithdrawalsCannotJumpQueuePriority() public {
        address recipient1 = makeAddr("RECIPIENT_1");
        address recipient2 = makeAddr("RECIPIENT_2");

        // user 1 creates a withdraw request
        _burnToken0AfterWithdraw(10e18, recipient1);

        // Simulate partial unstaking via `overseer`
        vm.deal(address(_withdrawalModule), 5 ether);
        _withdrawalModule.update();

        // user2 creates a smaller withdraw request
        _burnToken0AfterWithdraw(1e18, recipient2);

        // More ETH gets unstaked, but not enough to fulfill both requests
        vm.deal(address(_withdrawalModule), 10 ether);
        _withdrawalModule.update();

        // user2 tries to claim, but cannot because of queue priority
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_cannotYetClaim.selector);
        _withdrawalModule.claim(1);

        // user1 can claim
        _withdrawalModule.claim(0);
        assertEq(recipient1.balance, 10 ether);
        assertEq(address(_withdrawalModule).balance, 0);

        // More ETH gets unstaked via `overseer`
        vm.deal(address(_withdrawalModule), 1 ether);
        _withdrawalModule.update();

        // user2 can now claim
        _withdrawalModule.claim(1);
        assertEq(recipient2.balance, 1 ether);
    }

    function testLendingModuleProposal() public {
        assertEq(address(_withdrawalModule.lendingModule()), address(lendingModule));

        // Deposit some WETH into lending module
        vm.startPrank(owner);

        uint256 amount = 2 ether;
        _withdrawalModule.supplyToken1ToLendingPool(2 ether);
        assertEq(lendingModule.assetBalance(), 2 ether);

        vm.stopPrank();

        address lendingModuleMock = makeAddr("MOCK_LENDING_MODULE");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);

        vm.startPrank(owner);

        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooLow.selector);
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days - 1);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooHigh.selector);
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 7 days + 1);

        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);
        (address lendingModuleProposed, uint256 startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, lendingModuleMock);
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive.selector
        );
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.cancelLendingModuleProposal();

        vm.startPrank(owner);

        _withdrawalModule.cancelLendingModuleProposal();
        (lendingModuleProposed, startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.stopPrank();

        vm.revertToState(snapshot);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.setProposedLendingModule();

        vm.startPrank(owner);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.setProposedLendingModule();
        MockPool(_pool).setIsLocked(false);

        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive.selector
        );
        _withdrawalModule.setProposedLendingModule();

        vm.warp(block.timestamp + 3 days);

        uint256 preBalancePool = weth.balanceOf(address(_pool));
        _withdrawalModule.setProposedLendingModule();
        assertEq(address(_withdrawalModule.lendingModule()), lendingModuleMock);
        // Old lending module's asset (WETH) balance is now 0, all of it has been transferred to `_pool`
        uint256 postBalancePool = weth.balanceOf(address(_pool));
        assertEq(lendingModule.assetBalance(), 0);
        assertEq(postBalancePool - preBalancePool, amount);

        (lendingModuleProposed, startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal.selector
        );
        _withdrawalModule.setProposedLendingModule();

        vm.stopPrank();
    }

    function _burnToken0AfterWithdraw(uint256 amountToken0, address recipient) private {
        vm.prank(_pool);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__OnlySTEX.selector);
        _withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);

        uint256 preAmountToken0PendingUnstaking = _withdrawalModule.amountToken0PendingUnstaking();
        uint256 preAmountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        uint256 preAmountCumulative = _withdrawalModule.cumulativeAmountToken1LPWithdrawal();
        _withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);
        // No token0 has been unstaked
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), preAmountToken0PendingUnstaking);
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            _withdrawalModule.convertToToken1(amountToken0) + preAmountToken1PendingLPWithdrawal
        );
        uint256 preId = _withdrawalModule.idLPWithdrawal() - 1;
        (address to, uint96 amount, uint256 amountCumulative) = _withdrawalModule.LPWithdrawals(preId);
        assertEq(to, recipient);
        assertEq(amount, _withdrawalModule.convertToToken1(amountToken0));
        assertEq(amountCumulative, preAmountCumulative);
    }

    function _unstakeToken0Reserves(uint256 amount) private {
        uint256 initialToken0Reserves = _token0.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.unstakeToken0Reserves(initialToken0Reserves);

        uint256 preAmountToken0PendingUnstaking = _withdrawalModule.amountToken0PendingUnstaking();
        _token0.transfer(address(_withdrawalModule), amount);

        uint256 unstakeAmount = _token0.balanceOf(address(this));
        vm.startPrank(owner);
        _withdrawalModule.unstakeToken0Reserves(unstakeAmount);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), preAmountToken0PendingUnstaking + amount);

        vm.stopPrank();
    }
}
