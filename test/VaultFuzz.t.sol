// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SimpleVault.sol";
import "../src/MockUSDC.sol";

/// @title VaultFuzzTest
/// @notice Fuzz tests to verify that vault properties hold across arbitrary inputs.
contract VaultFuzzTest is Test {
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");

    MockUSDC internal usdc;
    SimpleVault internal vault;

    uint256 internal constant ONE_USDC = 1e6;

    function setUp() public {
        usdc = new MockUSDC("Mock USDC", "mUSDC", 6);
        vault = new SimpleVault(
            IERC20(address(usdc)),
            "Vault Share",
            "vUSDC",
            owner,
            feeRecipient,
            100, // 1% deposit fee
            50   // 0.5% withdraw fee
        );
        usdc.mint(alice, type(uint128).max);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// @dev Depositing any valid amount must mint > 0 shares and not revert.
    function testFuzz_deposit_alwaysMintsShares(uint128 assets) public {
        vm.assume(assets > 1); // avoid 0 revert and extreme dust edge cases

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGt(shares, 0, "must mint at least 1 share");
        assertEq(vault.balanceOf(alice), shares);
    }

    /// @dev Fee collected must be exactly fee_bps/10000 of deposited amount (rounded down).
    function testFuzz_depositFee_exactAmount(uint128 assets) public {
        vm.assume(assets > 0);
        uint256 expectedFee = (uint256(assets) * 100) / 10_000;

        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(usdc.balanceOf(feeRecipient), expectedFee);
    }

    /// @dev After depositing and fully redeeming (no yield), assets received <= deposited.
    function testFuzz_depositRedeem_neverProfitWithoutYield(uint128 assets) public {
        vm.assume(assets > 100); // avoid extreme dust rounding

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);

        assertLe(received, assets, "user cannot profit from deposit+redeem when no yield");
    }

    /// @dev convertToShares / convertToAssets should be approximately inverse of each other.
    function testFuzz_convertRoundtrip(uint128 assets) public {
        vm.assume(assets > 1e3); // avoid extreme dust

        // Seed vault
        vm.prank(alice);
        vault.deposit(10_000 * ONE_USDC, alice);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Due to rounding, assetsBack <= assets
        assertLe(assetsBack, assets, "convertToAssets(convertToShares(x)) <= x due to floor rounding");
    }

    /// @dev totalAssets() must equal the vault's actual token balance (net of fees sent out).
    function testFuzz_totalAssets_equalsVaultBalance(uint128 assets) public {
        vm.assume(assets > 1);

        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
    }
}
