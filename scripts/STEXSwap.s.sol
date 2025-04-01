// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {SovereignPoolSwapParams} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";

import {STEXAMM} from "src/STEXAMM.sol";

contract STEXSwapScript is Script, Test {
    using SafeERC20 for ERC20;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain Id not HyperEVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        STEXAMM stex = STEXAMM(
            payable(0xE20725BEa0aF2b125Fe21882385275cDbfA94298)
        );

        address token0 = stex.token0();
        address token1 = stex.token1();

        address tokenIn = token0;
        uint256 amount = 5 ether;

        uint256 amountOut = stex.getAmountOut(tokenIn, amount, false);

        console.log("amountOut expected: ", amountOut);

        SovereignPoolSwapParams memory params;
        params.isZeroToOne = tokenIn == token0;
        params.amountIn = amount;
        params.deadline = block.timestamp + 120;
        params.swapTokenOut = params.isZeroToOne ? token1 : token0;
        params.recipient = deployerAddress;

        ISovereignPool pool = ISovereignPool(stex.pool());

        console.log("pool: ", address(pool));

        ERC20(tokenIn).forceApprove(address(pool), params.amountIn);

        (uint256 amountInSwap, uint256 amountOutSwap) = pool.swap(params);

        console.log("amountIn: ", amountInSwap);
        console.log("amountOut: ", amountOutSwap);

        vm.stopBroadcast();
    }
}
