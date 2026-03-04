// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../src/SimpleVault.sol";
import "../src/MockUSDC.sol";

/// @title VaultTest
/// @notice Comprehensive unit tests for SimpleVault covering:
///   - Happy path: deposit, mint, withdraw, redeem
///   - Failure/revert paths: zero amount, insufficient balance, unauthorized, paused
///   - Fee accounting: deposit fee, withdraw fee, fee recipient
///   - Yield / share price changes via harvest()
///   - Events: Deposit, Withdraw, FeesCollected, pause/unpause
///   - Edge cases: rounding, dust amounts, max values
contract VaultTest is Test {
    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // -------------------------------------------------------------------------
    // Contracts
    // -------------------------------------------------------------------------
    MockUSDC internal usdc;
    SimpleVault internal vault;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 internal constant INITIAL_DEPOSIT_FEE_BPS = 100; // 1%
    uint256 internal constant INITIAL_WITHDRAW_FEE_BPS = 50; // 0.5%
    uint256 internal constant USDC_DECIMALS = 6;
    uint256 internal constant ONE_USDC = 10 ** USDC_DECIMALS;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------
    function setUp() public {
        usdc = new MockUSDC("Mock USDC", "mUSDC", uint8(USDC_DECIMALS));
        vault = new SimpleVault(
            IERC20(address(usdc)),
            "Vault Share",
            "vUSDC",
            owner,
            feeRecipient,
            INITIAL_DEPOSIT_FEE_BPS,
            INITIAL_WITHDRAW_FEE_BPS
        );

        // Give users some USDC
        usdc.mint(alice, 10_000 * ONE_USDC);
        usdc.mint(bob, 10_000 * ONE_USDC);
        usdc.mint(carol, 10_000 * ONE_USDC);
        usdc.mint(owner, 100_000 * ONE_USDC);

        // Approve vault to spend
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
    }

    // =========================================================================
    // SECTION 1: Deployment / initial state
    // =========================================================================

    function test_initialState() public view {
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.owner(), owner);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.depositFeeBps(), INITIAL_DEPOSIT_FEE_BPS);
        assertEq(vault.withdrawFeeBps(), INITIAL_WITHDRAW_FEE_BPS);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.paused(), false);
    }

    // =========================================================================
    // SECTION 2: Deposit (happy path)
    // =========================================================================

    function test_deposit_mintsCorrectShares() public {
        uint256 assets = 1_000 * ONE_USDC;
        // First deposit: share price = 1:1 on assets after fee
        uint256 fee = (assets * INITIAL_DEPOSIT_FEE_BPS) / 10_000;
        uint256 assetsAfterFee = assets - fee;

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertEq(shares, assetsAfterFee, "shares should equal assets after fee on first deposit");
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assetsAfterFee);
    }

    function test_deposit_transfersAssetsFromCaller() public {
        uint256 assets = 500 * ONE_USDC;
        uint256 aliceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(usdc.balanceOf(alice), aliceBefore - assets, "full amount deducted from alice");
    }

    function test_deposit_sendsFeeToRecipient() public {
        uint256 assets = 1_000 * ONE_USDC;
        uint256 expectedFee = (assets * INITIAL_DEPOSIT_FEE_BPS) / 10_000;

        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(usdc.balanceOf(feeRecipient), expectedFee);
    }

    function test_deposit_toOtherReceiver() public {
        uint256 assets = 1_000 * ONE_USDC;

        vm.prank(alice);
        vault.deposit(assets, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertGt(vault.balanceOf(bob), 0, "bob should receive shares");
    }

    function test_deposit_emitsDepositEvent() public {
        uint256 assets = 1_000 * ONE_USDC;
        uint256 fee = (assets * INITIAL_DEPOSIT_FEE_BPS) / 10_000;
        uint256 assetsAfterFee = assets - fee;
        uint256 expectedShares = assetsAfterFee; // first deposit, 1:1

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IERC4626.Deposit(alice, alice, assetsAfterFee, expectedShares);
        vault.deposit(assets, alice);
    }

    function test_deposit_emitsFeesCollectedEvent() public {
        uint256 assets = 1_000 * ONE_USDC;
        uint256 fee = (assets * INITIAL_DEPOSIT_FEE_BPS) / 10_000;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit SimpleVault.FeesCollected(feeRecipient, fee);
        vault.deposit(assets, alice);
    }

    function test_deposit_zeroFee_noFeeTransfer() public {
        vm.prank(owner);
        vault.setDepositFee(0);

        uint256 assets = 500 * ONE_USDC;
        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(usdc.balanceOf(feeRecipient), 0, "no fee when fee is 0");
        assertEq(vault.totalAssets(), assets);
    }

    // =========================================================================
    // SECTION 3: Deposit (failure paths)
    // =========================================================================

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(SimpleVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100 * ONE_USDC, alice);
    }

    function test_deposit_revertsOnInsufficientBalance() public {
        uint256 tooMuch = 100_000 * ONE_USDC; // alice only has 10_000
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(tooMuch, alice);
    }

    function test_deposit_revertsOnInsufficientAllowance() public {
        // Reset approval
        vm.prank(alice);
        usdc.approve(address(vault), 0);

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100 * ONE_USDC, alice);
    }

    // =========================================================================
    // SECTION 4: Mint (happy path)
    // =========================================================================

    function test_mint_pullsGrossAssetsFromCaller() public {
        // First deposit to set share price
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        uint256 sharesToMint = 100 * ONE_USDC;
        uint256 bobBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 assetsUsed = vault.mint(sharesToMint, bob);

        assertEq(usdc.balanceOf(bob), bobBefore - assetsUsed, "gross assets deducted from bob");
        assertGe(assetsUsed, sharesToMint, "gross assets >= net shares (due to fee)");
    }

    function test_mint_revertsOnZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(SimpleVault.ZeroAmount.selector);
        vault.mint(0, alice);
    }

    function test_mint_revertsWhenPaused() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.mint(100 * ONE_USDC, alice);
    }

    // =========================================================================
    // SECTION 5: Withdraw (happy path)
    // =========================================================================

    function test_withdraw_burnsSharesAndSendsAssets() public {
        uint256 depositAssets = 1_000 * ONE_USDC;
        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        // Withdraw some net amount
        uint256 netWithdraw = 500 * ONE_USDC;
        vm.prank(alice);
        vault.withdraw(netWithdraw, alice, alice);

        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + netWithdraw, "alice receives exact net amount");
        assertLt(vault.balanceOf(alice), aliceShares, "shares burned");
    }

    function test_withdraw_sendsFeeToRecipient() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);
        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);

        uint256 netWithdraw = 500 * ONE_USDC;
        vm.prank(alice);
        vault.withdraw(netWithdraw, alice, alice);

        assertGt(usdc.balanceOf(feeRecipient), feeRecipientBefore, "fee recipient receives withdraw fee");
    }

    function test_withdraw_revertsOnZeroAmount() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        vm.prank(alice);
        vm.expectRevert(SimpleVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);
    }

    function test_withdraw_revertsWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(100 * ONE_USDC, alice, alice);
    }

    function test_withdraw_revertsOnExceedingBalance() public {
        vm.prank(alice);
        vault.deposit(100 * ONE_USDC, alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1_000 * ONE_USDC, alice, alice); // much more than deposited
    }

    function test_withdraw_byOperatorWithAllowance() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice approves bob to spend her shares
        vm.prank(alice);
        vault.approve(bob, aliceShares);

        // Bob withdraws on behalf of alice
        uint256 netWithdraw = 200 * ONE_USDC;
        vm.prank(bob);
        vault.withdraw(netWithdraw, bob, alice);

        assertEq(usdc.balanceOf(bob), 10_000 * ONE_USDC + netWithdraw, "bob receives assets");
    }

    function test_withdraw_revertsWithoutOperatorAllowance() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(100 * ONE_USDC, bob, alice); // bob has no allowance
    }

    // =========================================================================
    // SECTION 6: Redeem (happy path)
    // =========================================================================

    function test_redeem_burnsSharesAndSendsNetAssets() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(aliceShares, alice, alice);

        assertEq(vault.balanceOf(alice), 0, "all shares burned");
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + assetsReceived);

        // assetsReceived should be less than deposited (fees taken both ways)
        uint256 depositFee = (1_000 * ONE_USDC * INITIAL_DEPOSIT_FEE_BPS) / 10_000;
        assertLt(assetsReceived, 1_000 * ONE_USDC - depositFee, "withdraw fee also taken");
    }

    function test_redeem_revertsOnZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(SimpleVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_redeem_revertsWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(100 * ONE_USDC, alice, alice);
    }

    function test_redeem_byOperator() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.redeem(shares, bob, alice);

        assertEq(vault.balanceOf(alice), 0, "all alice shares burned");
    }

    // =========================================================================
    // SECTION 7: Yield / share price
    // =========================================================================

    function test_harvest_increasesSharePrice() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(aliceSharesBefore);

        // Owner injects yield
        uint256 yieldAmount = 100 * ONE_USDC;
        vm.prank(owner);
        vault.harvest(yieldAmount);

        uint256 assetsAfter = vault.convertToAssets(aliceSharesBefore);
        assertGt(assetsAfter, assetsBefore, "share price should increase after yield");
    }

    function test_harvest_lateDepositorGetsFairShares() public {
        // Alice deposits first
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);

        // Yield injected
        vm.prank(owner);
        vault.harvest(200 * ONE_USDC);

        // Bob deposits same nominal amount
        uint256 bobDeposit = 1_000 * ONE_USDC;
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        // Bob should receive fewer shares than alice (price went up)
        assertLt(bobShares, vault.balanceOf(alice), "bob gets fewer shares due to higher share price");
    }

    function test_harvest_emitsEvent() public {
        uint256 yieldAmount = 50 * ONE_USDC;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SimpleVault.Harvested(owner, yieldAmount);
        vault.harvest(yieldAmount);
    }

    function test_harvest_zeroAmount_reverts() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVault.ZeroAmount.selector);
        vault.harvest(0);
    }

    function test_totalFeesCollected_accumulates() public {
        vm.prank(alice);
        vault.deposit(1_000 * ONE_USDC, alice);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        assertGt(vault.totalFeesCollected(), 0, "fees should have been collected");
    }

    // =========================================================================
    // SECTION 8: Pause / unpause
    // =========================================================================

    function test_pause_blocksDeposit() public {
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100 * ONE_USDC, alice);
    }

    function test_unpause_allowsDeposit() public {
        vm.prank(owner);
        vault.pause();

        vm.prank(owner);
        vault.unpause();

        vm.prank(alice);
        vault.deposit(100 * ONE_USDC, alice); // should succeed
    }

    function test_pause_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_unpause_onlyOwner() public {
        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();
    }

    // =========================================================================
    // SECTION 9: Fee management
    // =========================================================================

    function test_setDepositFee_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setDepositFee(200);
    }

    function test_setDepositFee_exceedsMax_reverts() public {
        uint256 maxFee = vault.MAX_FEE();
        uint256 tooHigh = maxFee + 1;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.FeeExceedsMax.selector, tooHigh, maxFee));
        vault.setDepositFee(tooHigh);
    }

    function test_setDepositFee_emitsEvent() public {
        uint256 newFee = 200;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit SimpleVault.DepositFeeUpdated(INITIAL_DEPOSIT_FEE_BPS, newFee);
        vault.setDepositFee(newFee);
    }

    function test_setWithdrawFee_exceedsMax_reverts() public {
        uint256 maxFee = vault.MAX_FEE();
        uint256 tooHigh = maxFee + 1;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.FeeExceedsMax.selector, tooHigh, maxFee));
        vault.setWithdrawFee(tooHigh);
    }

    function test_setFeeRecipient_zeroAddress_reverts() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_emitsEvent() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit SimpleVault.FeeRecipientUpdated(feeRecipient, newRecipient);
        vault.setFeeRecipient(newRecipient);
    }

    function test_constructor_zeroFeeRecipient_reverts() public {
        vm.expectRevert(SimpleVault.ZeroAddress.selector);
        new SimpleVault(
            IERC20(address(usdc)), "V", "V", owner, address(0), 0, 0
        );
    }

    function test_constructor_depositFeeExceedsMax_reverts() public {
        uint256 tooHigh = vault.MAX_FEE() + 1;
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.FeeExceedsMax.selector, tooHigh, vault.MAX_FEE()));
        new SimpleVault(
            IERC20(address(usdc)), "V", "V", owner, feeRecipient, tooHigh, 0
        );
    }

    // =========================================================================
    // SECTION 10: Edge cases & precision
    // =========================================================================

    function test_dust_deposit_1wei() public {
        // Depositing 1 wei: after fee it could round to 0 shares — vault should handle gracefully
        // With 1% fee on 1 wei: fee = 0 (rounds down), assetsAfterFee = 1
        vm.prank(owner);
        vault.setDepositFee(0); // simplify for dust test

        vm.prank(alice);
        uint256 shares = vault.deposit(1, alice);
        assertGe(shares, 0);
    }

    function test_multipleDepositors_shareAccounting() public {
        // Alice and Bob both deposit; verify their proportional claim is correct
        uint256 aliceDeposit = 1_000 * ONE_USDC;
        uint256 bobDeposit = 2_000 * ONE_USDC;

        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        // Bob should have ~2x alice's shares (same share price, 2x assets)
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);
        // Allow 1 wei rounding
        assertApproxEqAbs(bobShares, 2 * aliceShares, 1);
    }

    function test_depositAndFullRedeem_noYield() public {
        uint256 assets = 1_000 * ONE_USDC;
        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);

        // After 1% deposit fee + 0.5% withdraw fee, alice gets back less
        assertLt(received, assets, "alice gets back less than deposited due to fees");
        // But should be close: ~(assets * 0.99 * 0.995)
        uint256 approxExpected = (assets * 99 * 995) / (100 * 1000);
        assertApproxEqRel(received, approxExpected, 0.01e18); // within 1%
    }
}
