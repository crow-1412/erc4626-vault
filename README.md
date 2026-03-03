# ERC-4626 Vault

A production-quality ERC-4626 tokenized vault with deposit/withdraw fees, pausability, and yield injection — backed by a comprehensive Foundry test suite.

## Features

- **ERC-4626 compliant**: `deposit`, `mint`, `withdraw`, `redeem` with correct share accounting
- **Fee mechanism**: configurable deposit fee + withdraw fee (basis points, max 10%), sent to a dedicated fee recipient
- **Pausability**: owner can halt all vault operations in emergencies
- **Reentrancy guard**: all state-changing entrypoints are protected
- **Yield simulation**: `harvest()` lets the owner inject yield to increase share price
- **SafeERC20**: all token transfers use OpenZeppelin's safe wrappers

## Quick Start

```bash
# 1. Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Clone and build
git clone <repo-url> && cd erc4626-vault
forge install   # install dependencies
forge build     # compile

# 3. Run all tests
forge test -v
```

Expected output: **53 tests passing** (unit + fuzz + invariant).

## Project Structure

```
src/
  SimpleVault.sol       # ERC-4626 vault contract
  MockUSDC.sol          # ERC-20 mock for testing

test/
  VaultTest.t.sol       # 44 unit tests (happy path, revert, events, edge cases)
  VaultFuzz.t.sol       # 5 fuzz tests (1000 runs each)
  VaultInvariant.t.sol  # 4 invariant tests (256 runs x 32 depth)

.github/workflows/
  ci.yml                # GitHub Actions: forge test on every PR
```

## Test Strategy

### Unit Tests (`VaultTest.t.sol`)

Organized into 10 sections:

| Section | What's tested |
|---------|--------------|
| Deployment | Initial state, constructor validation |
| Deposit (happy) | Correct shares, fee accounting, events, receiver, zero-fee |
| Deposit (fail) | Zero amount, paused, insufficient balance/allowance |
| Mint | Gross asset pull, failure paths |
| Withdraw (happy) | Net asset delivery, fee, operator allowance, events |
| Withdraw (fail) | Zero, paused, exceeding balance, unauthorized |
| Redeem | Share burn, net assets, operator |
| Yield | Share price increase after harvest, late depositor dilution |
| Pause/Unpause | Owner-only, blocks all operations |
| Fee management | Owner-only, max limit, events, zero-address |

### Fuzz Tests (`VaultFuzz.t.sol`)

- `testFuzz_deposit_alwaysMintsShares` - any valid deposit mints at least 1 share
- `testFuzz_depositFee_exactAmount` - fee collected equals exact bps calculation
- `testFuzz_depositRedeem_neverProfitWithoutYield` - user can't profit from round-trip
- `testFuzz_convertRoundtrip` - `convertToAssets(convertToShares(x)) <= x`
- `testFuzz_totalAssets_equalsVaultBalance` - accounting invariant holds

### Invariant Tests (`VaultInvariant.t.sol`)

Four invariants verified across 256 x 8192 calls with random deposit/redeem/harvest sequences:

1. `totalAssets() == vault's USDC balance` - no phantom assets
2. `sum(userShares) <= totalSupply()` - no share duplication
3. `convertToAssets(totalSupply) <= totalAssets + 1` - no free lunch (+-1 rounding)
4. `totalFeesCollected` monotonically increases - fees never go backward

## Key Design Decision: Share Calculation Timing

`previewDeposit(assetsAfterFee)` is called **before** any token transfer. This ensures share price uses the pre-deposit `totalAssets()` state - the same approach OZ's ERC4626 uses internally. Calling it after would inflate `totalAssets()` and produce 0 shares on the first deposit (classic inflation vector).

## Running Individual Suites

```bash
# Unit tests only
forge test --match-path "test/VaultTest.t.sol" -v

# Fuzz tests with more runs
forge test --match-path "test/VaultFuzz.t.sol" --fuzz-runs 5000 -v

# Invariant tests
forge test --match-path "test/VaultInvariant.t.sol" -v

# Gas report
forge test --gas-report --match-path "test/VaultTest.t.sol"
```

## CI

GitHub Actions runs `forge test` on every push and PR to `main`. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
