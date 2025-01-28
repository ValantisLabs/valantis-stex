// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WETH} from "@solmate/tokens/WETH.sol";

import {DepositWrapper} from "src/DepositWrapper.sol";

contract DepositWrapperTest is Test {
    WETH weth;

    DepositWrapper nativeWrapper;

    address private _token1;

    function token1() external view returns (address) {
        return _token1;
    }

    function setUp() public {
        weth = new WETH();
        _token1 = address(weth);
        nativeWrapper = new DepositWrapper(address(weth), address(this));
    }

    function testDeploy() public {
        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(0), address(this));

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(weth), address(0));

        DepositWrapper nativeWrapperDeployment = new DepositWrapper(address(weth), address(this));
        assertEq(address(nativeWrapperDeployment.hamm()), address(this));
        assertEq(address(nativeWrapperDeployment.weth()), address(weth));

        _token1 = makeAddr("MOCK_TOKEN1");
        vm.expectRevert(DepositWrapper.DepositWrapper__constructor_invalidToken1.selector);
        new DepositWrapper(address(weth), address(this));
    }

    function testReceive() public {
        vm.expectRevert(DepositWrapper.DepositWrapper__receive_OnlyWETH9.selector);
        address(nativeWrapper).call{value: 1 ether}("");

        vm.deal(address(weth), 1 ether);

        vm.prank(address(weth));
        (bool success,) = address(nativeWrapper).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(nativeWrapper).balance, 1 ether);
    }
}
