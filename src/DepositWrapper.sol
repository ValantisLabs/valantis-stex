// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {SovereignPoolSwapParams} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";

/**
 * @notice Native token wrapper to deposit into Stake Exchange AMM.
 */
contract DepositWrapper is ReentrancyGuardTransient {
    using SafeERC20 for ERC20;
    using SafeERC20 for IWETH9;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error DepositWrapper__ZeroAddress();
    error DepositWrapper__constructor_invalidToken1();
    error DepositWrapper__receive_OnlyWETH9();

    /**
     *
     *  IMMUTABLES
     *
     */
    ISTEXAMM public immutable stex;
    IWETH9 public immutable weth;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _weth, address _stex) {
        if (_weth == address(0) || _stex == address(0)) {
            revert DepositWrapper__ZeroAddress();
        }
        stex = ISTEXAMM(_stex);
        weth = IWETH9(_weth);
        if (stex.token1() != _weth) {
            revert DepositWrapper__constructor_invalidToken1();
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert DepositWrapper__receive_OnlyWETH9();
        }
    }

    /**
     * @notice Helper function which wraps native token before depositing.
     * @param _minShares Minimum amount of LP token required.
     * @param _deadline Block timestamp after which this call expires.
     * @param _recipient Address to mint LP tokens for.
     * @return shares Amount of LP tokens minted during deposit.
     */
    function depositFromNative(uint256 _minShares, uint256 _deadline, address _recipient)
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        if (_recipient == address(0)) revert DepositWrapper__ZeroAddress();

        uint256 amount = msg.value;
        if (amount == 0) return 0;

        _wrapAndApprove(amount, address(stex));

        shares = stex.deposit(amount, _minShares, _deadline, _recipient);
    }

    /**
     * @notice Helper function which swaps token0 into token1, and then deposits into STEX AMM.
     * @param _amountToken0 Amount of token0 to swap.
     * @param _amountToken1Min Minimum amount of token1 required after swap.
     * @param _minShares Minimum amount of LP token required.
     * @param _deadline Block timestamp after which this call expires.
     * @param _recipient Address to mint LP tokens for.
     * @return shares Amount of LP tokens minted during deposit.
     */
    function depositFromToken0(
        uint256 _amountToken0,
        uint256 _amountToken1Min,
        uint256 _minShares,
        uint256 _deadline,
        address _recipient
    ) external nonReentrant returns (uint256 shares) {
        if (_recipient == address(0)) revert DepositWrapper__ZeroAddress();

        if (_amountToken0 == 0) return 0;

        ERC20 token0 = ERC20(stex.token0());
        token0.safeTransferFrom(msg.sender, address(this), _amountToken0);
        // WARNING: Do not donate tokens into this contract!
        uint256 amountToken0 = token0.balanceOf(address(this));

        ISovereignPool pool = ISovereignPool(stex.pool());

        token0.forceApprove(address(pool), amountToken0);
        SovereignPoolSwapParams memory swapParams;
        swapParams.isZeroToOne = true;
        swapParams.amountIn = amountToken0;
        swapParams.amountOutMin = _amountToken1Min;
        swapParams.deadline = _deadline;
        swapParams.swapTokenOut = address(weth);
        swapParams.recipient = address(this);

        (, uint256 amountToken1) = pool.swap(swapParams);

        weth.forceApprove(address(stex), amountToken1);
        shares = stex.deposit(amountToken1, _minShares, _deadline, _recipient);
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _wrapAndApprove(uint256 amount, address to) private {
        weth.deposit{value: amount}();
        weth.forceApprove(to, amount);
    }
}
