'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi';
import { VaultStats } from '@/lib/components/VaultStats';
import { DepositForm } from '@/lib/components/DepositForm';
import { RedeemForm } from '@/lib/components/RedeemForm';
import { VAULT_ADDRESS, USDC_ADDRESS } from '@/lib/contracts';

export default function Home() {
  const { address, isConnected } = useAccount();

  const isConfigured = Boolean(VAULT_ADDRESS && USDC_ADDRESS);

  return (
    <main className="min-h-screen bg-slate-50">
      {/* Header */}
      <header className="border-b border-slate-200 bg-white px-4 py-3">
        <div className="mx-auto flex max-w-3xl items-center justify-between">
          <div>
            <h1 className="text-lg font-bold text-slate-800">ERC-4626 Vault</h1>
            <p className="text-xs text-slate-500">Sepolia Testnet Demo</p>
          </div>
          <ConnectButton />
        </div>
      </header>

      <div className="mx-auto max-w-3xl px-4 py-8 space-y-6">
        {!isConfigured && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-800">
            <strong>Setup required:</strong> Add contract addresses to{' '}
            <code className="font-mono">.env.local</code> (see{' '}
            <code className="font-mono">.env.local.example</code>).
          </div>
        )}

        {!isConnected ? (
          <div className="rounded-xl border border-slate-200 bg-white p-8 text-center">
            <p className="text-slate-500 mb-4">Connect your wallet to interact with the vault.</p>
            <ConnectButton />
          </div>
        ) : (
          <>
            {/* Vault stats */}
            <section>
              <h2 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">
                Vault Stats
              </h2>
              <VaultStats userAddress={address!} />
            </section>

            {/* Actions */}
            <section className="grid gap-4 sm:grid-cols-2">
              <div className="rounded-xl border border-slate-200 bg-white p-5">
                <DepositForm userAddress={address!} />
              </div>
              <div className="rounded-xl border border-slate-200 bg-white p-5">
                <RedeemForm userAddress={address!} />
              </div>
            </section>

            {/* Footer links */}
            <section className="text-xs text-slate-400 text-center space-x-4">
              {VAULT_ADDRESS && (
                <a
                  href={`https://sepolia.etherscan.io/address/${VAULT_ADDRESS}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline hover:text-slate-600"
                >
                  Vault contract
                </a>
              )}
              {USDC_ADDRESS && (
                <a
                  href={`https://sepolia.etherscan.io/address/${USDC_ADDRESS}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline hover:text-slate-600"
                >
                  MockUSDC contract
                </a>
              )}
            </section>
          </>
        )}
      </div>
    </main>
  );
}
