'use client';

import { useReadContracts } from 'wagmi';
import { formatUnits } from 'viem';
import { VAULT_ADDRESS, USDC_ADDRESS, VAULT_ABI, ERC20_ABI } from '@/lib/contracts';
import type { Address } from 'viem';

interface VaultStatsProps {
  userAddress: Address;
}

export function VaultStats({ userAddress }: VaultStatsProps) {
  const { data, isLoading } = useReadContracts({
    contracts: [
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'totalAssets' },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'totalSupply' },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'convertToAssets', args: [1n * 10n ** 18n] },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'depositFeeBps' },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'withdrawFeeBps' },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: 'balanceOf', args: [userAddress] },
      { address: USDC_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf', args: [userAddress] },
    ],
    query: { refetchInterval: 6000 },
  });

  if (isLoading || !data) {
    return <div className="animate-pulse text-slate-400 text-sm">Loading vault stats…</div>;
  }

  const totalAssets = data[0].result as bigint | undefined;
  const totalSupply = data[1].result as bigint | undefined;
  const sharePrice = data[2].result as bigint | undefined;
  const depositFeeBps = data[3].result as bigint | undefined;
  const withdrawFeeBps = data[4].result as bigint | undefined;
  const userShares = data[5].result as bigint | undefined;
  const userUsdc = data[6].result as bigint | undefined;

  const fmt6 = (v: bigint | undefined) =>
    v !== undefined ? Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 4 }) : '—';

  const fmt18 = (v: bigint | undefined) =>
    v !== undefined ? Number(formatUnits(v, 18)).toLocaleString(undefined, { maximumFractionDigits: 6 }) : '—';

  const fmtBps = (v: bigint | undefined) =>
    v !== undefined ? `${(Number(v) / 100).toFixed(2)}%` : '—';

  // Share price: 1 svUSDC (1e18 shares) → ? mUSDC (6 decimals)
  const sharePriceDisplay =
    sharePrice !== undefined
      ? `${Number(formatUnits(sharePrice, 6)).toFixed(6)} mUSDC`
      : '—';

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      <Stat label="Total Assets" value={`${fmt6(totalAssets)} mUSDC`} />
      <Stat label="Total Shares" value={fmt18(totalSupply)} />
      <Stat label="Share Price" value={sharePriceDisplay} />
      <Stat label="Deposit Fee" value={fmtBps(depositFeeBps)} />
      <Stat label="Withdraw Fee" value={fmtBps(withdrawFeeBps)} />
      <Stat label="Your mUSDC" value={`${fmt6(userUsdc)} mUSDC`} />
      <Stat label="Your Shares" value={fmt18(userShares)} className="col-span-2 sm:col-span-1" />
    </div>
  );
}

function Stat({
  label,
  value,
  className = '',
}: {
  label: string;
  value: string;
  className?: string;
}) {
  return (
    <div className={`rounded-lg bg-white border border-slate-200 p-3 ${className}`}>
      <p className="text-xs text-slate-500 mb-1">{label}</p>
      <p className="font-semibold text-slate-800 truncate">{value}</p>
    </div>
  );
}
