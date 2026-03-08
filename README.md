# ERC-4626 Vault

A production-quality ERC-4626 tokenized vault with deposit/withdraw fees, pausability, and yield injection — backed by a comprehensive Foundry test suite and a Next.js frontend DApp.

## Live Demo (Sepolia)

| Contract | Address |
|----------|---------|
| SimpleVault | [0x8C187B2d8C2563eEc467c0B4E2f185a3A0CdC6cf](https://sepolia.etherscan.io/address/0x8C187B2d8C2563eEc467c0B4E2f185a3A0CdC6cf) |
| MockUSDC | [0xe903e39742A04C0e36958E99235c94dA115c7859](https://sepolia.etherscan.io/address/0xe903e39742A04C0e36958E99235c94dA115c7859) |

![DApp screenshot](docs/screenshot.png)

## Features

- **ERC-4626 compliant**: `deposit`, `mint`, `withdraw`, `redeem` with correct share accounting
- **Fee mechanism**: configurable deposit fee + withdraw fee (basis points, max 10%), sent to a dedicated fee recipient
- **Pausability**: owner can halt all vault operations in emergencies
- **Reentrancy guard**: all state-changing entrypoints are protected
- **Yield simulation**: `harvest()` lets the owner inject yield to increase share price
- **SafeERC20**: all token transfers use OpenZeppelin's safe wrappers
- **Frontend DApp**: Next.js 14 + wagmi v2 + RainbowKit — approve, deposit, and redeem in the browser

## Quick Start

### 1. Run the tests

```bash
# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash && foundryup

git clone <repo-url> && cd erc4626-vault
forge install   # install dependencies
forge test -v   # run all 55 tests
```

Expected: **55 tests passing** (unit + fuzz + invariant).

### 2. Deploy to Sepolia

```bash
cp .env.example .env
# Fill in PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY

source .env
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

The script prints the deployed addresses and the exact lines to paste into `frontend/.env.local`.

### 3. Run the frontend

```bash
cd frontend
cp .env.local.example .env.local
# Fill in NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID, NEXT_PUBLIC_SEPOLIA_RPC_URL,
# NEXT_PUBLIC_VAULT_ADDRESS, NEXT_PUBLIC_USDC_ADDRESS

npm install
npm run dev   # → http://localhost:3000
```

## Architecture

```
erc4626-vault/
├── src/
│   ├── SimpleVault.sol           # ERC-4626 vault with fee logic
│   └── MockUSDC.sol              # ERC-20 mock token (6 decimals)
├── test/
│   ├── VaultTest.t.sol           # 46 unit tests
│   ├── VaultFuzz.t.sol           # 5 fuzz tests (1 000 runs each)
│   └── VaultInvariant.t.sol      # 4 invariant tests (256 × 8 192 calls)
├── script/
│   └── Deploy.s.sol              # Foundry deploy script (MockUSDC + Vault)
├── frontend/
│   ├── src/app/                  # Next.js App Router pages
│   └── src/lib/
│       ├── wagmiConfig.ts        # wagmi v2 + RainbowKit config
│       ├── contracts.ts          # Hardcoded ABI + env-sourced addresses
│       └── components/
│           ├── VaultStats.tsx    # Live stats (refetch every 6 s)
│           ├── DepositForm.tsx   # Approve → Deposit two-step flow
│           ├── RedeemForm.tsx    # Redeem by amount or all
│           └── TxStatus.tsx      # Pending / success / error banner
├── .github/workflows/
│   └── ci.yml                    # Forge tests + Slither analysis
├── .env.example                  # Template for forge deploy vars
└── SECURITY.md                   # Vulnerability disclosure policy
```

## Test Strategy

### Unit Tests (`VaultTest.t.sol`)

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

- `testFuzz_deposit_alwaysMintsShares` — any valid deposit mints ≥ 1 share
- `testFuzz_depositFee_exactAmount` — fee equals exact bps calculation
- `testFuzz_depositRedeem_neverProfitWithoutYield` — no free lunch on round-trip
- `testFuzz_convertRoundtrip` — `convertToAssets(convertToShares(x)) <= x`
- `testFuzz_totalAssets_equalsVaultBalance` — accounting invariant holds

### Invariant Tests (`VaultInvariant.t.sol`)

Four invariants across 256 × 8 192 random calls:

1. `totalAssets() == vault's USDC balance` — no phantom assets
2. `sum(userShares) <= totalSupply()` — no share duplication
3. `convertToAssets(totalSupply) <= totalAssets + 1` — no free lunch (±1 rounding)
4. `totalFeesCollected` monotonically increases — fees never go backward

## Key Design Decision: Share Calculation Timing

`previewDeposit(assetsAfterFee)` is called **before** any token transfer. This ensures share price uses the pre-deposit `totalAssets()` state — the same approach OpenZeppelin's ERC4626 uses internally. Calling it after would inflate `totalAssets()` and produce 0 shares on the first deposit (classic inflation vector).

## CI

| Job | Trigger | Purpose |
|-----|---------|---------|
| `test` | Every push / PR | `forge test` — all 55 tests must pass |
| `slither` | Every push / PR | Static analysis, SARIF uploaded to Security tab |

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

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

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.
