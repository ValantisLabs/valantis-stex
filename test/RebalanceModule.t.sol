// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RebalanceModule} from "src/RebalanceModule.sol";
import {IRebalanceModule} from "src/interfaces/IRebalanceModule.sol";

contract MockTargetContract {
    ERC20Mock public token0;
    ERC20Mock public token1;

    bool public partialFill;

    constructor(address _token0, address _token1) {
        token0 = ERC20Mock(_token0);
        token1 = ERC20Mock(_token1);
    }

    function setPartialFill(bool _partialFill) external {
        partialFill = _partialFill;
    }

    function swapToken0ForToken1(uint256 amountToken0) external returns (uint256 amountToken1) {
        if (partialFill) {
            amountToken0 = amountToken0 / 2;
        }

        // Simulate a swap: transfer token0 from caller and mint token1 to caller
        token0.transferFrom(msg.sender, address(this), amountToken0);

        // Simulate getting token1 in return (1:1 ratio for simplicity)
        amountToken1 = amountToken0;
        token1.mint(msg.sender, amountToken1);

        return amountToken1;
    }

    function swapToken0ForToken1WithSlippage(uint256 amountToken0, uint256 slippageBps)
        external
        returns (uint256 amountToken1)
    {
        // Simulate a swap with slippage
        token0.transferFrom(msg.sender, address(this), amountToken0);

        // Calculate amount with slippage (slippageBps is in basis points)
        amountToken1 = (amountToken0 * (10000 - slippageBps)) / 10000;
        token1.mint(msg.sender, amountToken1);

        return amountToken1;
    }

    function failSwap() external pure {
        revert("Swap failed");
    }
}

contract RebalanceModuleTest is Test {
    RebalanceModule rebalanceModule;

    ERC20Mock token0;
    ERC20Mock token1;

    MockTargetContract mockTargetContract;
    MockTargetContract mockTargetContract2;

    address owner = makeAddr("OWNER");
    address withdrawalModule = makeAddr("WITHDRAWAL_MODULE");
    address pool = makeAddr("POOL");
    address recipient = makeAddr("RECIPIENT");
    address unauthorized = makeAddr("UNAUTHORIZED");

    uint256 constant INITIAL_BALANCE = 10000 ether;
    uint256 constant SWAP_AMOUNT = 1000 ether;
    uint256 constant MIN_TOKEN1_AMOUNT = 950 ether; // 5% slippage tolerance

    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        // Deploy mock tokens
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();

        // Mint initial balances
        token0.mint(withdrawalModule, INITIAL_BALANCE);
        token1.mint(withdrawalModule, INITIAL_BALANCE);

        // Deploy mock target contracts
        mockTargetContract = new MockTargetContract(address(token0), address(token1));
        mockTargetContract2 = new MockTargetContract(address(token0), address(token1));

        // Deploy rebalance module
        rebalanceModule = new RebalanceModule(withdrawalModule, pool, owner);

        // Transfer tokens to rebalance module for testing
        vm.prank(withdrawalModule);
        token0.transfer(address(rebalanceModule), SWAP_AMOUNT);
    }

    function testConstructor() public {
        // Test valid deployment
        RebalanceModule newModule = new RebalanceModule(withdrawalModule, pool, owner);
        assertEq(newModule.withdrawalModule(), withdrawalModule);
        assertEq(newModule.pool(), pool);
        assertEq(newModule.owner(), owner);

        // Test zero address validation
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        new RebalanceModule(address(0), pool, owner);

        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        new RebalanceModule(withdrawalModule, address(0), owner);

        vm.expectRevert();
        new RebalanceModule(withdrawalModule, pool, address(0));
    }

    function testRebalance_Success() public {
        // Prepare rebalance payload
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = SWAP_AMOUNT;

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, SWAP_AMOUNT);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        // Record initial balances
        uint256 initialToken0Balance = token0.balanceOf(withdrawalModule);
        uint256 initialToken1Balance = token1.balanceOf(withdrawalModule);
        uint256 initialPoolToken0Balance = token0.balanceOf(pool);

        // Execute rebalance
        vm.prank(withdrawalModule);
        bytes4 result = rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);

        // Verify return value
        assertEq(result, IRebalanceModule.rebalance.selector);

        // Verify token1 was transferred to withdrawal module
        assertEq(token1.balanceOf(withdrawalModule), initialToken1Balance + SWAP_AMOUNT);

        // Verify no remaining token0 in rebalance module
        assertEq(token0.balanceOf(address(rebalanceModule)), 0);

        // Verify no token0 was sent to pool (since all was swapped)
        assertEq(token0.balanceOf(pool), initialPoolToken0Balance);
    }

    function testRebalance_MultipleTargets() public {
        // Prepare rebalance payload with multiple targets
        uint256[] memory amountToken0Array = new uint256[](2);
        amountToken0Array[0] = SWAP_AMOUNT / 2;
        amountToken0Array[1] = SWAP_AMOUNT / 2;

        address[] memory targetAddresses = new address[](2);
        targetAddresses[0] = address(mockTargetContract);
        targetAddresses[1] = address(mockTargetContract2);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, SWAP_AMOUNT / 2);
        payloads[1] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, SWAP_AMOUNT / 2);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        // Execute rebalance
        vm.prank(withdrawalModule);
        bytes4 result = rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);

        // Verify return value
        assertEq(result, IRebalanceModule.rebalance.selector);

        // Verify token1 was received
        assertEq(token1.balanceOf(withdrawalModule), INITIAL_BALANCE + SWAP_AMOUNT);
    }

    function testRebalance_WithRemainingToken0() public {
        token0.burn(address(rebalanceModule), token0.balanceOf(address(rebalanceModule)));

        uint256 swapAmount = 2 ether;
        vm.prank(withdrawalModule);
        token0.transfer(address(rebalanceModule), swapAmount);

        mockTargetContract.setPartialFill(true);

        // Prepare rebalance payload for only half the balance
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = swapAmount;

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, swapAmount);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        uint256 initialPoolToken0Balance = token0.balanceOf(pool);

        // Execute rebalance
        vm.prank(withdrawalModule);
        rebalanceModule.rebalance(swapAmount / 2, payload);

        // Verify remaining token0 was sent to pool
        assertEq(token0.balanceOf(pool), initialPoolToken0Balance + swapAmount / 2);
        assertEq(token0.balanceOf(address(rebalanceModule)), 0);
    }

    function testRebalance_AccessControl() public {
        bytes memory payload =
            abi.encode(address(token0), address(token1), new uint256[](0), new address[](0), new bytes[](0));

        // Test unauthorized access
        vm.expectRevert(RebalanceModule.RebalanceModule__onlyWithdrawalModule.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);

        vm.prank(unauthorized);
        vm.expectRevert(RebalanceModule.RebalanceModule__onlyWithdrawalModule.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_InvalidAmountToken1Min() public {
        bytes memory payload =
            abi.encode(address(token0), address(token1), new uint256[](0), new address[](0), new bytes[](0));

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_InvalidAmountToken1Min.selector);
        rebalanceModule.rebalance(0, payload);
    }

    function testRebalance_ZeroAddresses() public {
        bytes memory payload = abi.encode(
            address(0), // token0
            address(token1),
            new uint256[](0),
            new address[](0),
            new bytes[](0)
        );

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);

        payload = abi.encode(
            address(token0),
            address(0), // token1
            new uint256[](0),
            new address[](0),
            new bytes[](0)
        );

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_InvalidArrayLengths() public {
        uint256[] memory amountToken0Array = new uint256[](1);
        address[] memory targetAddresses = new address[](2); // Different length
        targetAddresses[0] = address(mockTargetContract);
        targetAddresses[1] = address(mockTargetContract2);

        bytes[] memory payloads = new bytes[](1);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_InvalidPayloadArrayLength.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_ZeroTargetAddress() public {
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = SWAP_AMOUNT;

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(0); // Zero address

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, SWAP_AMOUNT);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_InvalidAmountToken0() public {
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = 0; // Zero amount

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, 0);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_InvalidAmountToken0.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_InsufficientToken0Balance() public {
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = SWAP_AMOUNT * 2; // More than available

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.swapToken0ForToken1.selector, SWAP_AMOUNT * 2);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_InsufficientToken0Received.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_TargetCallFailed() public {
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = SWAP_AMOUNT;

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(MockTargetContract.failSwap.selector);

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_TargetCallFailed.selector);
        rebalanceModule.rebalance(MIN_TOKEN1_AMOUNT, payload);
    }

    function testRebalance_InsufficientToken1Received() public {
        // Create a target that returns less token1 than expected
        uint256[] memory amountToken0Array = new uint256[](1);
        amountToken0Array[0] = SWAP_AMOUNT;

        address[] memory targetAddresses = new address[](1);
        targetAddresses[0] = address(mockTargetContract);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            MockTargetContract.swapToken0ForToken1WithSlippage.selector,
            SWAP_AMOUNT,
            1000 // 10% slippage
        );

        bytes memory payload =
            abi.encode(address(token0), address(token1), amountToken0Array, targetAddresses, payloads);

        // Set minimum token1 amount higher than what we'll receive
        uint256 highMinAmount = SWAP_AMOUNT; // We'll only get 90% of this

        vm.prank(withdrawalModule);
        vm.expectRevert(RebalanceModule.RebalanceModule__rebalance_InsufficientToken1Received.selector);
        rebalanceModule.rebalance(highMinAmount, payload);
    }

    function testSweep() public {
        vm.prank(unauthorized);
        vm.expectRevert(); // Ownable revert
        rebalanceModule.sweep(address(token0), recipient);

        vm.prank(owner);
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        rebalanceModule.sweep(address(0), recipient);

        vm.prank(owner);
        vm.expectRevert(RebalanceModule.RebalanceModule__ZeroAddress.selector);
        rebalanceModule.sweep(address(token0), address(0));

        token0.burn(address(rebalanceModule), 1000 ether);

        // Try to sweep when balance is 0
        vm.prank(owner);
        rebalanceModule.sweep(address(token0), recipient);

        vm.prank(owner);
        rebalanceModule.sweep(address(token1), recipient);

        // No balance updates
        assertEq(token0.balanceOf(recipient), 0);
        assertEq(token1.balanceOf(recipient), 0);

        // Transfer some tokens to rebalance module
        vm.prank(withdrawalModule);
        token0.transfer(address(rebalanceModule), 100 ether);

        vm.prank(withdrawalModule);
        token1.transfer(address(rebalanceModule), 50 ether);

        // Sweep token0
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(token0), recipient, 100 ether);
        rebalanceModule.sweep(address(token0), recipient);

        assertEq(token1.balanceOf(recipient), 0);
        assertEq(token0.balanceOf(address(recipient)), 100 ether);

        // Sweep token1
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(token1), recipient, 50 ether);
        rebalanceModule.sweep(address(token1), recipient);

        assertEq(token1.balanceOf(recipient), 50 ether);
        assertEq(token1.balanceOf(address(rebalanceModule)), 0);
    }
}
