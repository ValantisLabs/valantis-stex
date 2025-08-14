// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILendingModule} from "../interfaces/ILendingModule.sol";

/**
 * @notice Wrapper contract that allows its `manager` to lend an underlying `asset`
 *         on multiple lending markets, defined by `ILendingModule`.
 */
contract MultiMarketLendingModule is ILendingModule, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /**
     *
     *  EVENTS
     *
     */
    event DepositWeightsSet(uint16[] depositWeightBipsArray);
    event Initialized(address[] lendingModuleArray, LendingModuleConfig[] lendingModuleConfigArray);
    event ManagerFeeClaimed(address indexed recipient, uint256 amount);
    event Sweep(address indexed token, address indexed recipient, uint256 balance);
    event TokenSweepManagerUpdated(address tokenSweepManager);
    event WithdrawWeightsSet(uint16[] withdrawWeightBipsArray);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error MultiMarketLendingModule__InvalidManagerFeeBips();
    error MultiMarketLendingModule__NotInitialized();
    error MultiMarketLendingModule__OnlyManager();
    error MultiMarketLendingModule__OnlyTokenSweepManager();
    error MultiMarketLendingModule__ZeroAddress();
    error MultiMarketLendingModule__deposit_InvalidAmount();
    error MultiMarketLendingModule__deposit_PartialDepositNotAllowed();
    error MultiMarketLendingModule__initialize_AlreadyInitialized();
    error MultiMarketLendingModule__initialize_DuplicateLendingModule();
    error MultiMarketLendingModule__initialize_ExceededMaxLendingModules();
    error MultiMarketLendingModule__initialize_InvalidArrayLength();
    error MultiMarketLendingModule__initialize_InconsistentArrayLength();
    error MultiMarketLendingModule__initialize_InvalidOwner();
    error MultiMarketLendingModule__initialize_InvalidAsset();
    error MultiMarketLendingModule__initialize_InvalidDepositWeights();
    error MultiMarketLendingModule__initialize_InvalidWithdrawWeights();
    error MultiMarketLendingModule__setDepositWeights_InvalidArrayLength();
    error MultiMarketLendingModule__setDepositWeights_InvalidWeights();
    error MultiMarketLendingModule__setWithdrawWeights_InvalidArrayLength();
    error MultiMarketLendingModule__setWithdrawWeights_InvalidWeights();
    error MultiMarketLendingModule__withdraw_InvalidAmount();
    error MultiMarketLendingModule__withdraw_InsufficientAmountReceived();
    error MultiMarketLendingModule__withdraw_InsufficientBalance();
    error MultiMarketLendingModule__withdraw_ExcessiveAmountReceived();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;

    /**
     * @notice Maximum number of lending modules that can be initialized.
     */
    uint256 private constant MAX_LENDING_MODULES = 10;

    /**
     *
     *  STRUCTS
     *
     */

    /**
     * @notice Configuration for a lending module.
     * @param depositWeightBips Weight of the lending module in the `deposit` allocation.
     * @param withdrawWeightBips Weight of the lending module in the `withdraw` allocation.
     */
    struct LendingModuleConfig {
        uint16 depositWeightBips;
        uint16 withdrawWeightBips;
    }

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice ERC-20 token to be supplied.
     */
    address public immutable asset;

    /**
     * @notice Address of the manager, which can deposit and withdraw `asset`.
     */
    address public immutable manager;

    /**
     * @notice Manager fee, in bips.
     * @dev Must be less than or equal to 50%.
     */
    uint256 public immutable managerFeeBips;

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @notice Total principal amount of `asset` token deposited into the set of lending modules,
     *         excluding any accrued yield and manager fees.
     */
    uint256 public totalPrincipal;

    /**
     * @notice Accounts for due yield when withdrawals exceed the total principal.
     * @dev This is used to ensure that the manager can claim the due yield when
     *      withdrawals exceed the total principal.
     */
    uint256 public virtualYield;

    /**
     * @notice Total amount of `asset` token manager fees already claimed by the manager.
     */
    uint256 public totalManagerClaimed;

    /**
     * @notice Role which is able to call `sweep`.
     * @dev It can sweep any stuck token balances.
     */
    address public tokenSweepManager;

    /**
     * @notice Set of Lending Module addresses.
     */
    EnumerableSet.AddressSet private _lendingModules;

    /**
     * @notice Configuration for each lending module in `_lendingModules`.
     */
    mapping(address => LendingModuleConfig) private _lendingModuleConfigs;

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyTokenSweepManager() {
        if (msg.sender != tokenSweepManager) {
            revert MultiMarketLendingModule__OnlyTokenSweepManager();
        }
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert MultiMarketLendingModule__OnlyManager();
        }
        _;
    }

    modifier onlyWhenInitialized() {
        if (_lendingModules.length() == 0) {
            revert MultiMarketLendingModule__NotInitialized();
        }
        _;
    }

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _asset, address _owner, address _manager, address _tokenSweepManager, uint256 _managerFeeBips)
        Ownable(_owner)
    {
        if (_asset == address(0) || _tokenSweepManager == address(0) || _manager == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }

        if (_managerFeeBips > BIPS / 2) {
            revert MultiMarketLendingModule__InvalidManagerFeeBips();
        }

        tokenSweepManager = _tokenSweepManager;
        asset = _asset;
        manager = _manager;
        managerFeeBips = _managerFeeBips;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns amount of asset token owned by this contract's position
     *         across all lending modules.
     * @dev WARNING: This must NOT decrease as utilization/borrowing increases.
     *      This represents the total amount of asset token, plus any accrued yield,
     *      minus manager fees, that is owed to this contract,
     *      even when the lending modules have temporarily insufficient liquidity.
     */
    function assetBalance() public view override returns (uint256) {
        uint256 totalBalance = _getTotalBalance();

        uint256 managerFee = _getManagerFee(totalBalance);

        return totalBalance > managerFee ? totalBalance - managerFee : 0;
    }

    /**
     * @notice Returns the amount of yield claimable by the manager.
     */
    function managerFeeClaimable() public view returns (uint256) {
        uint256 totalBalance = _getTotalBalance();

        return _getManagerFee(totalBalance);
    }

    /**
     * @notice Returns the configuration for a lending module.
     * @param _lendingModule Address of the lending module.
     */
    function getLendingModuleConfig(address _lendingModule) external view returns (LendingModuleConfig memory) {
        return _lendingModuleConfigs[_lendingModule];
    }

    /**
     * @notice Returns the set of lending modules.
     */
    function lendingModules() external view returns (address[] memory) {
        return _lendingModules.values();
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Initializes the multi-market lending module.
     * @param _lendingModuleArray Array of lending module addresses.
     * @param _lendingModuleConfigArray Array of lending module config parameters.
     * @dev Only callable by the current `owner`.
     */
    function initialize(address[] memory _lendingModuleArray, LendingModuleConfig[] memory _lendingModuleConfigArray)
        external
        onlyOwner
    {
        if (_lendingModules.length() > 0) {
            revert MultiMarketLendingModule__initialize_AlreadyInitialized();
        }

        if (_lendingModuleArray.length > MAX_LENDING_MODULES) {
            revert MultiMarketLendingModule__initialize_ExceededMaxLendingModules();
        }

        if (_lendingModuleArray.length == 0) {
            revert MultiMarketLendingModule__initialize_InvalidArrayLength();
        }

        if (_lendingModuleConfigArray.length != _lendingModuleArray.length) {
            revert MultiMarketLendingModule__initialize_InconsistentArrayLength();
        }

        uint256 totalDepositWeightBips;
        uint256 totalWithdrawWeightBips;
        for (uint256 i = 0; i < _lendingModuleArray.length; i++) {
            address lendingModule = _lendingModuleArray[i];

            if (lendingModule == address(0)) {
                revert MultiMarketLendingModule__ZeroAddress();
            }

            if (Ownable(lendingModule).owner() != address(this)) {
                revert MultiMarketLendingModule__initialize_InvalidOwner();
            }

            // Sanity check that it is possible to query `assetBalance`
            ILendingModule(lendingModule).assetBalance();

            bool success = _lendingModules.add(lendingModule);
            if (!success) {
                revert MultiMarketLendingModule__initialize_DuplicateLendingModule();
            }

            LendingModuleConfig memory lendingModuleConfig = _lendingModuleConfigArray[i];

            _lendingModuleConfigs[lendingModule] = lendingModuleConfig;

            totalDepositWeightBips += lendingModuleConfig.depositWeightBips;
            totalWithdrawWeightBips += lendingModuleConfig.withdrawWeightBips;
        }

        // Weights must sum to one, in bips
        if (totalDepositWeightBips != BIPS) {
            revert MultiMarketLendingModule__initialize_InvalidDepositWeights();
        }

        if (totalWithdrawWeightBips != BIPS) {
            revert MultiMarketLendingModule__initialize_InvalidWithdrawWeights();
        }

        emit Initialized(_lendingModuleArray, _lendingModuleConfigArray);
    }

    /**
     * @notice Sets the weights for each lending module in the `deposit` allocation.
     * @param _depositWeightBipsArray Array of weights, in bips, for each lending module.
     * @dev Only callable by the current `owner`.
     */
    function setDepositWeights(uint16[] memory _depositWeightBipsArray) external onlyOwner onlyWhenInitialized {
        if (_depositWeightBipsArray.length != _lendingModules.length()) {
            revert MultiMarketLendingModule__setDepositWeights_InvalidArrayLength();
        }

        uint256 totalDepositWeightBips;
        for (uint256 i = 0; i < _lendingModules.length(); i++) {
            address lendingModule = _lendingModules.at(i);
            uint16 weight = _depositWeightBipsArray[i];

            _lendingModuleConfigs[lendingModule].depositWeightBips = weight;

            totalDepositWeightBips += weight;
        }
        // Weights must sum to one, in bips
        if (totalDepositWeightBips != BIPS) {
            revert MultiMarketLendingModule__setDepositWeights_InvalidWeights();
        }

        emit DepositWeightsSet(_depositWeightBipsArray);
    }

    /**
     * @notice Sets the weights for each lending module in the `withdraw` allocation.
     * @param _withdrawWeightBipsArray Array of weights, in bips, for each lending module.
     * @dev Only callable by the current `owner`.
     */
    function setWithdrawWeights(uint16[] memory _withdrawWeightBipsArray) external onlyOwner onlyWhenInitialized {
        if (_withdrawWeightBipsArray.length != _lendingModules.length()) {
            revert MultiMarketLendingModule__setWithdrawWeights_InvalidArrayLength();
        }

        uint256 totalWithdrawWeightBips;
        for (uint256 i = 0; i < _lendingModules.length(); i++) {
            address lendingModule = _lendingModules.at(i);
            uint16 weight = _withdrawWeightBipsArray[i];

            _lendingModuleConfigs[lendingModule].withdrawWeightBips = weight;

            totalWithdrawWeightBips += weight;
        }

        // Weights must sum to one, in bips
        if (totalWithdrawWeightBips != BIPS) {
            revert MultiMarketLendingModule__setWithdrawWeights_InvalidWeights();
        }

        emit WithdrawWeightsSet(_withdrawWeightBipsArray);
    }

    /**
     * @notice Claims the manager fee on the yield accrued across all lending modules.
     * @param _recipient Address to receive the manager fee.
     * @dev Only callable by the current `owner`.
     */
    function claimManagerFee(address _recipient) external onlyOwner {
        if (_recipient == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }

        uint256 claimable = managerFeeClaimable();
        if (claimable > 0) {
            // Cannot withdraw more than due manager fees
            uint256 amountClaimed = _withdraw(claimable, claimable, assetBalance(), _recipient);

            totalManagerClaimed += amountClaimed;

            emit ManagerFeeClaimed(_recipient, amountClaimed);
        }
    }

    /**
     * @notice Sets the address of the token sweep manager.
     * @param _tokenSweepManager Address of the token sweep manager.
     * @dev Only callable by the current `tokenSweepManager`.
     */
    function setTokenSweepManager(address _tokenSweepManager) external onlyTokenSweepManager {
        if (_tokenSweepManager == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }

        tokenSweepManager = _tokenSweepManager;

        emit TokenSweepManagerUpdated(_tokenSweepManager);
    }

    /**
     * @notice Deposits `asset` into the set of lending modules.
     * @param _amount Amount of `asset` token to deposit.
     * @dev Only the `manager` can deposit `asset` into the set of lending modules.
     */
    function deposit(uint256 _amount) external override onlyManager onlyWhenInitialized {
        if (_amount == 0) {
            revert MultiMarketLendingModule__deposit_InvalidAmount();
        }

        IERC20 token = IERC20(asset);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amountRemaining = _amount;
        uint256 preBalance = token.balanceOf(address(this));
        for (uint256 i = 0; i < _lendingModules.length(); i++) {
            address lendingModule = _lendingModules.at(i);
            LendingModuleConfig memory lendingModuleConfig = _lendingModuleConfigs[lendingModule];

            uint256 amountToDeposit = Math.min(
                Math.mulDiv(
                    _amount,
                    lendingModuleConfig.depositWeightBips,
                    BIPS,
                    Math.Rounding.Ceil // rounding up to avoid dust left-over
                ),
                amountRemaining
            );

            if (amountToDeposit == 0) {
                continue;
            }

            amountRemaining -= amountToDeposit;

            token.forceApprove(lendingModule, amountToDeposit);
            ILendingModule(lendingModule).deposit(amountToDeposit);
        }

        uint256 amountDeposited = preBalance - token.balanceOf(address(this));
        if (amountDeposited != _amount || amountRemaining > 0) {
            revert MultiMarketLendingModule__deposit_PartialDepositNotAllowed();
        }

        // Update total principal
        totalPrincipal += _amount;
    }

    /**
     * @notice Withdraws `asset` from the set of lending modules.
     * @param _amount Amount of `asset` token to withdraw.
     * @param _recipient Address to receive the withdrawn `asset` token.
     * @dev Only the `manager` can withdraw `asset` from the set of lending modules.
     */
    function withdraw(uint256 _amount, address _recipient) external override onlyManager onlyWhenInitialized {
        if (_amount == 0) {
            revert MultiMarketLendingModule__withdraw_InvalidAmount();
        }

        if (_recipient == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }

        // Cannot withdraw more than the total principal, plus earned yield,
        // minus due manager fees
        uint256 maxWithdraw = assetBalance();
        _withdraw(_amount, maxWithdraw, maxWithdraw, _recipient);
    }

    /**
     * @notice Sweep token balances which have been locked into this contract.
     * @dev Only callable by `tokenSweepManager`.
     * @param _token Token address to claim balances for.
     * @param _recipient Recipient of `_token` balance.
     */
    function sweep(address _token, address _recipient) external onlyTokenSweepManager {
        if (_token == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }
        if (_recipient == address(0)) {
            revert MultiMarketLendingModule__ZeroAddress();
        }

        IERC20 token = IERC20(_token);

        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(_recipient, balance);

            emit Sweep(_token, _recipient, balance);
        }
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _getTotalBalance() private view returns (uint256 totalBalance) {
        for (uint256 i = 0; i < _lendingModules.length(); i++) {
            totalBalance += ILendingModule(_lendingModules.at(i)).assetBalance();
        }
    }

    function _getManagerFee(uint256 totalBalance) private view returns (uint256) {
        uint256 totalNetYield = totalBalance > totalPrincipal ? totalBalance - totalPrincipal : 0;

        totalNetYield += virtualYield;

        uint256 totalManagerClaimable = Math.mulDiv(totalNetYield, managerFeeBips, BIPS);

        return totalManagerClaimable > totalManagerClaimed ? totalManagerClaimable - totalManagerClaimed : 0;
    }

    function _withdraw(uint256 amount, uint256 maxWithdraw, uint256 totalBalance, address recipient)
        private
        returns (uint256 amountReceived)
    {
        // Cannot withdraw in excess
        if (amount > maxWithdraw) {
            revert MultiMarketLendingModule__withdraw_InsufficientBalance();
        }

        bool isFullWithdraw = amount == totalBalance;

        IERC20 token = IERC20(asset);

        uint256 amountRemaining = amount;
        uint256 recipientPreBalance = token.balanceOf(recipient);
        for (uint256 i = 0; i < _lendingModules.length(); i++) {
            address lendingModule = _lendingModules.at(i);
            LendingModuleConfig memory lendingModuleConfig = _lendingModuleConfigs[lendingModule];

            uint256 amountToWithdraw;

            if (isFullWithdraw) {
                // If full withdraw, withdraw the full balance of the lending module,
                // without relying on the withdrawal weight.
                amountToWithdraw = ILendingModule(lendingModule).assetBalance();
            } else {
                amountToWithdraw = Math.min(
                    Math.mulDiv(
                        amount,
                        lendingModuleConfig.withdrawWeightBips,
                        BIPS,
                        Math.Rounding.Ceil // rounding up to avoid dust left-over
                    ),
                    amountRemaining
                );

                // Avoid potential reverts by ensuring that the amount to withdraw
                // does not exceed the total withdrawable amount (assetBalance)
                amountToWithdraw = Math.min(amountToWithdraw, ILendingModule(lendingModule).assetBalance());
            }

            if (amountToWithdraw == 0) {
                continue;
            }

            amountRemaining -= amountToWithdraw;

            // WARNING: This might temporarily revert if:
            // 1) Lending Module has insufficient liqudity due to high utilization
            // 2) `amountWithdraw` is greater than the Lending Module's available liquidity.
            // If 2), `owner` is required to adjust withdrawal weights proportionally.
            // If 1), `manager` needs to wait for the Lending Module to have sufficient liquidity.
            ILendingModule(lendingModule).withdraw(amountToWithdraw, recipient);
        }

        uint256 recipientPostBalance = token.balanceOf(recipient);
        if (recipientPostBalance < recipientPreBalance + amount) {
            revert MultiMarketLendingModule__withdraw_InsufficientAmountReceived();
        }

        amountReceived = recipientPostBalance - recipientPreBalance;

        // Cannot withdraw in excess
        if (amountReceived > maxWithdraw) {
            revert MultiMarketLendingModule__withdraw_ExcessiveAmountReceived();
        }

        // Update total principal and virtual yield
        if (totalPrincipal > amountReceived) {
            totalPrincipal -= amountReceived;
        } else {
            virtualYield += (amountReceived - totalPrincipal);
            totalPrincipal = 0;
        }
    }
}
