// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SimpleVault
/// @notice An ERC-4626 compliant vault with deposit/withdraw fees, pausability, and role-based access.
/// @dev Inherits OpenZeppelin's ERC4626 implementation. Fees are taken from assets on deposit/withdraw.
contract SimpleVault is ERC4626, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE = 1_000; // 10% max

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Fee in basis points charged on deposit (taken from deposited assets).
    uint256 public depositFeeBps;

    /// @notice Fee in basis points charged on withdrawal (taken from withdrawn assets).
    uint256 public withdrawFeeBps;

    /// @notice Address that receives collected fees.
    address public feeRecipient;

    /// @notice Total fees collected, in underlying asset units.
    uint256 public totalFeesCollected;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeesCollected(address indexed recipient, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error FeeExceedsMax(uint256 fee, uint256 max);
    error ZeroAddress();
    error ZeroAmount();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address feeRecipient_,
        uint256 depositFeeBps_,
        uint256 withdrawFeeBps_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(owner_) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (depositFeeBps_ > MAX_FEE) revert FeeExceedsMax(depositFeeBps_, MAX_FEE);
        if (withdrawFeeBps_ > MAX_FEE) revert FeeExceedsMax(withdrawFeeBps_, MAX_FEE);

        feeRecipient = feeRecipient_;
        depositFeeBps = depositFeeBps_;
        withdrawFeeBps = withdrawFeeBps_;
    }

    // -------------------------------------------------------------------------
    // Admin: pause
    // -------------------------------------------------------------------------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Admin: fee management
    // -------------------------------------------------------------------------

    function setDepositFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE) revert FeeExceedsMax(newFeeBps, MAX_FEE);
        emit DepositFeeUpdated(depositFeeBps, newFeeBps);
        depositFeeBps = newFeeBps;
    }

    function setWithdrawFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE) revert FeeExceedsMax(newFeeBps, MAX_FEE);
        emit WithdrawFeeUpdated(withdrawFeeBps, newFeeBps);
        withdrawFeeBps = newFeeBps;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    // -------------------------------------------------------------------------
    // Admin: simulate yield (for testing/demo purposes)
    // -------------------------------------------------------------------------

    /// @notice Owner can inject yield by transferring assets directly and calling this.
    /// This increases totalAssets() and thus the share price.
    /// In production this would be replaced by an actual yield strategy.
    function harvest(uint256 amount) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
    }

    // -------------------------------------------------------------------------
    // ERC-4626 overrides with fee logic
    // -------------------------------------------------------------------------

    /// @dev Hook called before any token transfer (mint/burn/transfer). Checks pause state.
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();

        uint256 fee = _computeFee(assets, depositFeeBps);
        uint256 assetsAfterFee = assets - fee;

        // Compute shares BEFORE transfer so totalAssets() reflects pre-deposit state
        shares = previewDeposit(assetsAfterFee);

        // Pull full assets from caller
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Forward fee to recipient
        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
            totalFeesCollected += fee;
            emit FeesCollected(feeRecipient, fee);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assetsAfterFee, shares);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();

        // Calculate gross assets needed before fee
        uint256 assetsAfterFee = previewMint(shares);
        uint256 grossAssets = _grossUpForFee(assetsAfterFee, depositFeeBps);
        uint256 fee = grossAssets - assetsAfterFee;

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), grossAssets);

        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
            totalFeesCollected += fee;
            emit FeesCollected(feeRecipient, fee);
        }

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assetsAfterFee, shares);

        return grossAssets;
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();

        // Gross up: caller wants `assets` after fee, so we must withdraw more
        uint256 grossAssets = _grossUpForFee(assets, withdrawFeeBps);
        uint256 fee = grossAssets - assets;

        shares = previewWithdraw(grossAssets);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }
        _burn(owner_, shares);

        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
            totalFeesCollected += fee;
            emit FeesCollected(feeRecipient, fee);
        }
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, grossAssets, shares);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();

        uint256 grossAssets = previewRedeem(shares);
        uint256 fee = _computeFee(grossAssets, withdrawFeeBps);
        assets = grossAssets - fee;

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }
        _burn(owner_, shares);

        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
            totalFeesCollected += fee;
            emit FeesCollected(feeRecipient, fee);
        }
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, grossAssets, shares);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _computeFee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return (amount * feeBps) / FEE_DENOMINATOR;
    }

    /// @dev Given a net amount desired after fee, compute the gross amount needed.
    /// grossAmount = netAmount * FEE_DENOMINATOR / (FEE_DENOMINATOR - feeBps)
    function _grossUpForFee(uint256 netAmount, uint256 feeBps) internal pure returns (uint256) {
        if (feeBps == 0) return netAmount;
        return (netAmount * FEE_DENOMINATOR + FEE_DENOMINATOR - feeBps - 1) / (FEE_DENOMINATOR - feeBps);
    }
}
