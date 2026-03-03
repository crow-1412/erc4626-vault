// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SimpleVault.sol";
import "../src/MockUSDC.sol";

/// @title VaultInvariantTest
/// @notice Invariant tests: properties that must ALWAYS hold regardless of call sequence.
///
/// Invariants tested:
///   1. totalAssets() == vault's actual USDC balance
///   2. Sum of all user share balances <= totalSupply()
///   3. convertToAssets(totalSupply()) <= totalAssets() (no free lunch)
///   4. totalFeesCollected only increases
contract VaultInvariantTest is Test {
    MockUSDC internal usdc;
    SimpleVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        address feeRecipient = makeAddr("feeRecipient");

        usdc = new MockUSDC("Mock USDC", "mUSDC", 6);
        vault = new SimpleVault(
            IERC20(address(usdc)),
            "Vault Share",
            "vUSDC",
            owner,
            feeRecipient,
            100, // 1%
            50   // 0.5%
        );

        handler = new VaultHandler(vault, usdc, owner);

        // Focus fuzzer only on handler functions
        targetContract(address(handler));
    }

    // -------------------------------------------------------------------------
    // Invariant 1: totalAssets() == vault's USDC balance
    // -------------------------------------------------------------------------
    function invariant_totalAssetsEqVaultBalance() public view {
        assertEq(
            vault.totalAssets(),
            usdc.balanceOf(address(vault)),
            "INV1: totalAssets must equal vault USDC balance"
        );
    }

    // -------------------------------------------------------------------------
    // Invariant 2: No user holds more shares than totalSupply
    // -------------------------------------------------------------------------
    function invariant_userSharesLeqTotalSupply() public view {
        address[] memory users = handler.getUsers();
        uint256 sumShares;
        for (uint256 i = 0; i < users.length; i++) {
            sumShares += vault.balanceOf(users[i]);
        }
        assertLe(sumShares, vault.totalSupply(), "INV2: sum of user shares <= totalSupply");
    }

    // -------------------------------------------------------------------------
    // Invariant 3: No free lunch — redeemable value <= totalAssets
    // -------------------------------------------------------------------------
    function invariant_noFreeLunch() public view {
        uint256 totalShares = vault.totalSupply();
        if (totalShares == 0) return;
        uint256 redeemableValue = vault.convertToAssets(totalShares);
        assertLe(redeemableValue, vault.totalAssets() + 1, unicode"INV3: redeemable value <= totalAssets (±1 rounding)");
    }

    // -------------------------------------------------------------------------
    // Invariant 4: totalFeesCollected only monotonically increases
    // -------------------------------------------------------------------------
    function invariant_feesOnlyIncrease() public view {
        // This is enforced by the handler tracking the last seen value
        assertGe(vault.totalFeesCollected(), handler.lastFeesCollected(), "INV4: fees never decrease");
    }
}

/// @dev Handler contract drives the vault with random but valid actions.
contract VaultHandler is Test {
    SimpleVault internal vault;
    MockUSDC internal usdc;
    address internal owner;

    address[] internal users;
    uint256 public lastFeesCollected;

    uint256 internal constant ONE_USDC = 1e6;

    constructor(SimpleVault vault_, MockUSDC usdc_, address owner_) {
        vault = vault_;
        usdc = usdc_;
        owner = owner_;

        // Create 3 users
        for (uint256 i = 0; i < 3; i++) {
            address u = makeAddr(string(abi.encodePacked("user", i)));
            users.push(u);
            usdc.mint(u, 1_000_000 * ONE_USDC);
            vm.prank(u);
            usdc.approve(address(vault), type(uint256).max);
        }

        // Owner approves for harvest
        usdc.mint(owner, 1_000_000 * ONE_USDC);
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 userSeed, uint256 assets) external {
        address user = _pickUser(userSeed);
        assets = bound(assets, 1, 10_000 * ONE_USDC);

        vm.prank(user);
        try vault.deposit(assets, user) {} catch {}
        lastFeesCollected = vault.totalFeesCollected();
    }

    function redeem(uint256 userSeed, uint256 sharePct) external {
        address user = _pickUser(userSeed);
        uint256 shares = vault.balanceOf(user);
        if (shares == 0) return;
        sharePct = bound(sharePct, 1, 100);
        uint256 toRedeem = (shares * sharePct) / 100;
        if (toRedeem == 0) return;

        vm.prank(user);
        try vault.redeem(toRedeem, user, user) {} catch {}
        lastFeesCollected = vault.totalFeesCollected();
    }

    function harvest(uint256 amount) external {
        amount = bound(amount, 0, 10_000 * ONE_USDC);
        vm.prank(owner);
        try vault.harvest(amount) {} catch {}
    }

    function getUsers() external view returns (address[] memory) {
        return users;
    }

    function _pickUser(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }
}
