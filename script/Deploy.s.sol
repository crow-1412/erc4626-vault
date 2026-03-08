// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/SimpleVault.sol";

/// @notice Deploy MockUSDC + SimpleVault to any EVM network.
/// Required env vars:
///   PRIVATE_KEY           — deployer private key (with 0x prefix)
/// Optional env vars (fall back to safe defaults):
///   FEE_RECIPIENT         — address receiving fees (defaults to deployer)
///   DEPOSIT_FEE_BPS       — deposit fee in basis points (default: 100 = 1%)
///   WITHDRAW_FEE_BPS      — withdraw fee in basis points (default: 50 = 0.5%)
contract Deploy is Script {
    uint256 constant MINT_AMOUNT = 1_000_000 * 1e6; // 1,000,000 mUSDC

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Optional config with sane defaults
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        uint256 depositFeeBps = vm.envOr("DEPOSIT_FEE_BPS", uint256(100));
        uint256 withdrawFeeBps = vm.envOr("WITHDRAW_FEE_BPS", uint256(50));

        console.log("=== Deploy Config ===");
        console.log("Deployer:        ", deployer);
        console.log("Fee recipient:   ", feeRecipient);
        console.log("Deposit fee bps: ", depositFeeBps);
        console.log("Withdraw fee bps:", withdrawFeeBps);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MockUSDC (6 decimals, like real USDC)
        MockUSDC usdc = new MockUSDC("Mock USDC", "mUSDC", 6);
        console.log("MockUSDC deployed:", address(usdc));

        // 2. Deploy SimpleVault
        SimpleVault vault = new SimpleVault(
            IERC20(address(usdc)),
            "SimpleVault Shares",
            "svUSDC",
            deployer,
            feeRecipient,
            depositFeeBps,
            withdrawFeeBps
        );
        console.log("SimpleVault deployed:", address(vault));

        // 3. Mint demo tokens to deployer
        usdc.mint(deployer, MINT_AMOUNT);
        console.log("Minted 1,000,000 mUSDC to deployer");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("MockUSDC:   ", address(usdc));
        console.log("SimpleVault:", address(vault));
        console.log("");
        console.log("Add to frontend/.env.local:");
        console.log("NEXT_PUBLIC_USDC_ADDRESS=", address(usdc));
        console.log("NEXT_PUBLIC_VAULT_ADDRESS=", address(vault));
    }
}
