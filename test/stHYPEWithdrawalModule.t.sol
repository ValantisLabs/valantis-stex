// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";
import {AaveLendingModule} from "src/AaveLendingModule.sol";
import {STEXLens} from "src/STEXLens.sol";

contract stHYPEWithdrawalModuleTest is Test {
    stHYPEWithdrawalModule _withdrawalModule;

    WETH weth;
    MockStHype private _token0;

    STEXLens stexLens;

    MockOverseer overseer;

    MockLendingPool lendingPool;
    AaveLendingModule lendingModule;

    address private _pool = makeAddr("MOCK_POOL");

    address public owner = makeAddr("OWNER");

    function setUp() public {
        overseer = new MockOverseer();

        _token0 = new MockStHype();
        weth = new WETH();

        stexLens = new STEXLens();

        lendingPool = new MockLendingPool(address(weth));
        assertEq(lendingPool.underlyingAsset(), address(weth));
        assertEq(lendingPool.lendingPoolYieldToken(), address(lendingPool));

        _withdrawalModule = new stHYPEWithdrawalModule(address(overseer), owner);
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

        vm.startPrank(owner);
        // AMM will be mocked to make testing more flexible
        _withdrawalModule.setSTEX(address(this));
        assertEq(_withdrawalModule.stex(), address(this));
        vm.stopPrank();

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        uint256 shares = _token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(_token0.totalSupply(), shares);
        assertEq(_token0.balanceOf(address(this)), 100 ether);
        assertEq(address(_token0).balance, 100 ether);

        _token0.approve(address(_withdrawalModule), 100 ether);

        vm.deal(address(overseer), 10 ether);
    }

    /**
     * AMM mock functions **
     */
    function token0() external view returns (address) {
        return address(_token0);
    }

    function token1() external view returns (address) {
        return address(weth);
    }

    function pool() external view returns (address) {
        return _pool;
    }

    function withdrawalModule() external view returns (address) {
        return address(_withdrawalModule);
    }

    function unstakeToken0Reserves(uint256 _amountToken0) external {}

    function supplyToken1Reserves(uint256 amount) external {
        weth.transfer(msg.sender, amount);
    }

    /**
     * **
     */
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

    function testToken0Accounting() public view {
        // token0 is rebase, hence conversion to and from token1 amounts is 1:1
        assertEq(_withdrawalModule.convertToToken0(1 ether), 1 ether);
        assertEq(_withdrawalModule.convertToToken1(1 ether), 1 ether);

        assertEq(_token0.sharesOf(address(this)), _withdrawalModule.token0SharesOf(address(this)));
        assertEq(_token0.balanceToShares(1 ether), _withdrawalModule.token0BalanceToShares(1 ether));
        assertEq(_token0.sharesToBalance(1 ether), _withdrawalModule.token0SharesToBalance(1 ether));
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

    function testAmount0Correction() public {
        int256 amount0Correction = _withdrawalModule.amount0Correction();
        assertEq(amount0Correction, int256(0));

        uint256 snapshot = vm.snapshotState();

        _unstakeToken0Reserves(0.1 ether);

        amount0Correction = _withdrawalModule.amount0Correction();
        assertEq(amount0Correction, int256(_token0.sharesToBalance(0.1 ether)));

        vm.revertToState(snapshot);

        // unstake 0.5 eth + add LP claim for 1 eth
        address recipient = makeAddr("MOCK_RECIPIENT");
        _addClaimForPendingUnstakingShares(recipient, 1 ether, 0.5 ether);

        amount0Correction = _withdrawalModule.amount0Correction();
        assertEq(amount0Correction, -int256(_token0.sharesToBalance(0.5 ether)));
    }

    function testSetOverseerCommunityCode() public {
        bytes32 emptyHash = keccak256("");
        assertEq(keccak256(bytes(_withdrawalModule.overseerCommunityCode())), emptyHash);

        string memory code = "valantis";

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.setOverseerCommunityCode(code);

        vm.startPrank(owner);

        _withdrawalModule.setOverseerCommunityCode(code);
        assertEq(keccak256(bytes(_withdrawalModule.overseerCommunityCode())), keccak256(bytes(code)));

        vm.stopPrank();
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

    function testAddClaimForPreUnstakingShares() public {
        uint256 shares = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");

        vm.startPrank(recipient);

        // Only callable by STEX
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__OnlySTEX.selector);
        _withdrawalModule.addClaimForPreUnstakingShares(shares, recipient);

        vm.stopPrank();

        _withdrawalModule.addClaimForPreUnstakingShares(shares, recipient);
        assertEq(_withdrawalModule.idLPWithdrawal(), 1);
        LPWithdrawalRequest memory request = _withdrawalModule.getLPWithdrawals(0);
        assertEq(request.shares, shares);
        assertEq(request.recipient, recipient);
        assertEq(request.epochId, 0);
        assertEq(_withdrawalModule.amountToken0SharesPreUnstakingLPWithdrawal(), shares);
    }

    function testAddClaimForPendingUnstakingShares() public {
        uint256 shares = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");
        uint256 sharesToUnstake = 0.5 ether;

        _addClaimForPendingUnstakingShares(recipient, shares, sharesToUnstake);
    }

    function testUnstakeToken0Reserves() public {
        uint256 snapshot = vm.snapshotState();

        _unstakeToken0Reserves(3 ether);

        vm.revertToState(snapshot);

        address recipient = makeAddr("MOCK_RECIPIENT");
        _withdrawalModule.addClaimForPreUnstakingShares(1 ether, recipient);
        assertEq(_withdrawalModule.amountToken0SharesPreUnstakingLPWithdrawal(), 1 ether);
        assertEq(_withdrawalModule.idLPWithdrawal(), 1);
        LPWithdrawalRequest memory request = _withdrawalModule.getLPWithdrawals(0);
        assertEq(request.shares, 1 ether);
        assertEq(request.epochId, 0);
        assertEq(request.recipient, recipient);

        _token0.transfer(address(_withdrawalModule), 1 ether - 1);

        vm.startPrank(owner);

        // When there are prior LP withdrawals pending,
        // the owner must unstake enough token0 to fulfill those
        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__unstakeToken0Reserves_insufficientShares.selector
        );
        _withdrawalModule.unstakeToken0Reserves(1 ether - 1);

        vm.stopPrank();
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
        // Only callable by owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.update();

        vm.startPrank(owner);

        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__update_zeroUnstakingRequestsStarted.selector);
        _withdrawalModule.update();

        vm.stopPrank();

        _unstakeToken0Reserves(3 ether);
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(_withdrawalModule.amountToken0SharesPendingUnstaking(), _token0.balanceToShares(3 ether));
        assertEq(_withdrawalModule.amountToken0SharesPreUnstakingLPWithdrawal(), 0);

        vm.startPrank(owner);

        uint256 snapshot = vm.snapshotState();
        uint256 snapshot2 = vm.snapshotState();
        uint256 snapshot3 = vm.snapshotState();

        _withdrawalModule.update();
        // No pending LP withdrawals and no slashing,
        // so the entire amount of ETH unstaked goes back into the pool as WETH
        assertEq(weth.balanceOf(address(_pool)), 3 ether);
        assertEq(weth.balanceOf(address(_withdrawalModule)), 0);

        // unstaking epoch id already processed
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__update_epochIdAlreadyProcessed.selector);
        _withdrawalModule.update();

        vm.revertToState(snapshot3);

        // Scenario where overseer has faulty `redeem`
        overseer.setIsCompromised(true);

        // zero ETH balance after unstaking is not allowed
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__update_invalidExchangeRate.selector);
        _withdrawalModule.update();

        vm.revertToState(snapshot2);

        // In this scenario, two recipients make a claim for a portion of ETH
        // of the current unstaking epoch
        address recipient1 = makeAddr("MOCK_RECIPIENT_1");
        address recipient2 = makeAddr("MOCK_RECIPIENT_2");

        vm.startPrank(address(this));
        _withdrawalModule.addClaimForPendingUnstakingShares(1 ether, recipient1);
        _withdrawalModule.addClaimForPendingUnstakingShares(1.5 ether, recipient2);
        vm.stopPrank();

        assertEq(stexLens.canClaim(address(this), 0), false);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_epochIdNotProcessed.selector);
        _withdrawalModule.claim(0);

        assertEq(stexLens.canClaim(address(this), 1), false);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_epochIdNotProcessed.selector);
        _withdrawalModule.claim(1);

        vm.startPrank(owner);

        _withdrawalModule.update();
        assertEq(weth.balanceOf(address(_pool)), 0.5 ether);
        // 1 ether stays in withdrawal module to be claimed by the recipients
        assertEq(weth.balanceOf(address(_withdrawalModule)), 2.5 ether);

        vm.stopPrank();

        assertEq(stexLens.canClaim(address(this), 0), true);
        _withdrawalModule.claim(0);
        assertEq(recipient1.balance, 1 ether);

        assertEq(stexLens.canClaim(address(this), 0), false);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_alreadyClaimed.selector);
        _withdrawalModule.claim(0);

        assertEq(stexLens.canClaim(address(this), 1), true);
        _withdrawalModule.claim(1);
        assertEq(recipient2.balance, 1.5 ether);

        assertEq(stexLens.canClaim(address(this), 1), false);
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_alreadyClaimed.selector);
        _withdrawalModule.claim(1);

        assertEq(weth.balanceOf(address(_withdrawalModule)), 0);

        vm.revertToState(snapshot);

        // Scenario where unstaking request cannot be redeemed in overseer,
        // but is not yet completed

        vm.deal(address(overseer), 0);
        assertEq(address(overseer).balance, 0);

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(stHYPEWithdrawalModule.stHYPEWithdrawalModule__update_burnIdNotCompleted.selector, 0)
        );
        _withdrawalModule.update();
        vm.stopPrank();
    }

    function testLendingModuleProposal() public {
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

        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive.selector
        );
        _withdrawalModule.setProposedLendingModule();

        vm.warp(block.timestamp + 3 days);

        _withdrawalModule.setProposedLendingModule();
        assertEq(address(_withdrawalModule.lendingModule()), lendingModuleMock);

        (lendingModuleProposed, startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.expectRevert(
            stHYPEWithdrawalModule.stHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal.selector
        );
        _withdrawalModule.setProposedLendingModule();

        vm.stopPrank();
    }

    function _addClaimForPendingUnstakingShares(address recipient, uint256 shares, uint256 sharesToUnstake) private {
        vm.startPrank(recipient);

        // Only callable by STEX
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__OnlySTEX.selector);
        _withdrawalModule.addClaimForPendingUnstakingShares(shares, recipient);

        vm.stopPrank();

        uint256 preIdLPWithdrawal = _withdrawalModule.idLPWithdrawal();
        uint256 preAmountToken0SharesPendingUnstakingLPWithdrawal =
            _withdrawalModule.amountToken0SharesPendingUnstakingLPWithdrawal();
        uint256 preEpochId = _withdrawalModule.currentEpochId();
        LPWithdrawalRequest memory request;
        if (preEpochId == 0) {
            _withdrawalModule.addClaimForPendingUnstakingShares(shares, recipient);

            // No state changes, since there is no active pending unstaking request
            assertEq(_withdrawalModule.idLPWithdrawal(), preIdLPWithdrawal);
            request = _withdrawalModule.getLPWithdrawals(preIdLPWithdrawal);
            assertEq(request.shares, 0);
            assertEq(request.recipient, address(0));
            assertEq(request.epochId, 0);
            assertEq(
                _withdrawalModule.amountToken0SharesPendingUnstakingLPWithdrawal(),
                preAmountToken0SharesPendingUnstakingLPWithdrawal
            );
        }

        _unstakeToken0Reserves(sharesToUnstake);

        _withdrawalModule.addClaimForPendingUnstakingShares(shares, recipient);
        assertEq(_withdrawalModule.idLPWithdrawal(), preIdLPWithdrawal + 1);
        request = _withdrawalModule.getLPWithdrawals(preIdLPWithdrawal);
        assertEq(request.shares, shares);
        assertEq(request.recipient, recipient);
        assertEq(request.epochId, 0);
        assertEq(_withdrawalModule.currentEpochId(), preEpochId + 1);
        assertEq(_withdrawalModule.amountToken0SharesPendingUnstakingLPWithdrawal(), shares);
    }

    function _unstakeToken0Reserves(uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.unstakeToken0Reserves(amount);

        uint256 preToken0SharesPendingUnstaking = _withdrawalModule.amountToken0SharesPendingUnstaking();
        _token0.transfer(address(_withdrawalModule), amount);

        uint256 unstakeAmount = _token0.balanceOf(address(this));
        vm.startPrank(owner);
        _withdrawalModule.unstakeToken0Reserves(amount);
        assertEq(
            _withdrawalModule.amountToken0SharesPendingUnstaking(),
            preToken0SharesPendingUnstaking + _token0.balanceToShares(amount)
        );

        // Can only have one pending unstaking request at a time
        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__unstakeToken0Reserves_pendingUnstaking.selector);
        _withdrawalModule.unstakeToken0Reserves(amount);

        vm.stopPrank();
    }
}
