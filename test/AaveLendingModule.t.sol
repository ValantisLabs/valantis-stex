// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WETH} from "@solmate/tokens/WETH.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {AaveLendingModule} from "src/AaveLendingModule.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";

contract AaveLendingModuleTest is Test {
    AaveLendingModule lendingModule;
    MockLendingPool lendingPool;

    WETH weth;

    ERC20Mock mockToken;

    address tokenSweepManager = makeAddr("MOCK_TOKEN_SWEEP_MANAGER");
    address recipient = makeAddr("MOCK_RECIPIENT");

    function setUp() public {
        weth = new WETH();

        mockToken = new ERC20Mock();

        lendingPool = new MockLendingPool(address(weth));
        lendingModule = new AaveLendingModule(
            address(lendingPool),
            lendingPool.lendingPoolYieldToken(),
            address(weth),
            address(this),
            tokenSweepManager,
            2
        );
        assertEq(lendingModule.yieldToken(), lendingPool.lendingPoolYieldToken());
        assertEq(lendingModule.asset(), address(weth));
        assertEq(lendingModule.owner(), address(this));
        assertEq(lendingModule.tokenSweepManager(), tokenSweepManager);
        assertEq(lendingModule.referralCode(), 2);
    }

    function testTokenSweepManager() public {
        address newTokenSweepManager = makeAddr("MOCK_NEW_TOKEN_SWEEP_MANAGER");

        vm.expectRevert(AaveLendingModule.AaveLendingModule__OnlyTokenSweepManager.selector);
        lendingModule.setTokenSweepManager(newTokenSweepManager);

        vm.startPrank(tokenSweepManager);

        lendingModule.setTokenSweepManager(newTokenSweepManager);
        assertEq(lendingModule.tokenSweepManager(), newTokenSweepManager);

        vm.stopPrank();
    }

    function testSweep() public {
        vm.expectRevert(AaveLendingModule.AaveLendingModule__OnlyTokenSweepManager.selector);
        lendingModule.sweep(address(mockToken), recipient);

        vm.startPrank(tokenSweepManager);

        vm.expectRevert(AaveLendingModule.AaveLendingModule__ZeroAddress.selector);
        lendingModule.sweep(address(0), recipient);

        vm.expectRevert(AaveLendingModule.AaveLendingModule__ZeroAddress.selector);
        lendingModule.sweep(address(mockToken), address(0));

        vm.expectRevert(AaveLendingModule.AaveLendingModule__sweep_assetCannotBeSweeped.selector);
        lendingModule.sweep(address(weth), recipient);

        address yieldToken = lendingModule.yieldToken();
        vm.expectRevert(AaveLendingModule.AaveLendingModule__sweep_yieldTokenCannotBeSweeped.selector);
        lendingModule.sweep(yieldToken, recipient);

        mockToken.mint(address(lendingModule), 10 ether);
        lendingModule.sweep(address(mockToken), recipient);
        assertEq(mockToken.balanceOf(recipient), 10 ether);

        vm.stopPrank();
    }
}
