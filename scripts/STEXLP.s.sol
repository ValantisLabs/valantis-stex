// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXLens} from "src/STEXLens.sol";
import {STEXAMM} from "src/STEXAMM.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";

contract STEXLPScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain Id not HyperEVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        STEXLens stexLens = STEXLens(
            0xC1C9430044861D6e34745345EFCA710B482daC19
        );
        STEXAMM stex = STEXAMM(
            payable(0x45f2b4A4cA043F44F468C126a03332D202626C7a)
        );

        // Uncomment for deposits
        /*uint256 amount = 0.2 ether;
        uint256 shares = stexLens.getSharesForDeposit(address(stex), amount);

        DepositWrapper depositWrapper = DepositWrapper(
            payable(0xF25d259C16d986956bc5edcBFfCbc6503440b545)
        );
        uint256 sharesDeposited = depositWrapper.depositFromNative{
            value: amount
        }((shares * 9999) / 10_000, block.timestamp + 120, deployerAddress);

        console.log("shares expected: ", shares);
        console.log("shares deposited: ", sharesDeposited);*/

        // Uncomment for withdrawals
        /*uint256 amount = 1e16;
        bool isInstantWithdrawal = true;

        (uint256 amount0, uint256 amount1) = stexLens.getAmountsForWithdraw(
            address(stex),
            amount,
            isInstantWithdrawal
        );

        console.log("amount0 expected: ", amount0);
        console.log("amount1 expected: ", amount1);

        (uint256 amount0Withdraw, uint256 amount1Withdraw) = stex.withdraw(
            amount,
            amount0,
            amount1,
            block.timestamp + 120,
            deployerAddress,
            true,
            isInstantWithdrawal
        );

        console.log("amount0 withdraw: ", amount0Withdraw);
        console.log("amount1 withdraw: ", amount1Withdraw);*/

        vm.stopBroadcast();
    }
}
