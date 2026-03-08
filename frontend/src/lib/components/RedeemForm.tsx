'use client';

import { useState, useEffect } from 'react';
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { VAULT_ADDRESS, VAULT_ABI } from '@/lib/contracts';
import { TxStatus, type TxState } from './TxStatus';
import type { Address } from 'viem';

interface RedeemFormProps {
  userAddress: Address;
}

export function RedeemForm({ userAddress }: RedeemFormProps) {
  const [amount, setAmount] = useState('');
  const [txState, setTxState] = useState<TxState>({ status: 'idle' });

  // Fetch user's share balance
  const { data: maxShares, refetch: refetchBalance } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: 'maxRedeem',
    args: [userAddress],
    query: { refetchInterval: 6000 },
  });

  const amountBn = (() => {
    try {
      const n = parseFloat(amount);
      if (!amount || isNaN(n) || n <= 0) return undefined;
      return parseUnits(amount, 18); // shares have 18 decimals
    } catch {
      return undefined;
    }
  })();

  const sharesToRedeem = amountBn;
  const hasShares = maxShares !== undefined && maxShares > 0n;

  // Write hooks
  const { writeContractAsync } = useWriteContract();
  const [pendingHash, setPendingHash] = useState<`0x${string}` | undefined>();

  const { isLoading: isConfirming, isSuccess: isConfirmed, data: receipt } =
    useWaitForTransactionReceipt({ hash: pendingHash });

  useEffect(() => {
    if (isConfirmed && receipt) {
      setTxState({ status: 'success', hash: receipt.transactionHash });
      setPendingHash(undefined);
      refetchBalance();
    }
  }, [isConfirmed, receipt, refetchBalance]);

  async function handleRedeem(shares: bigint) {
    try {
      setTxState({
        status: 'pending',
        description: `Redeeming ${formatUnits(shares, 18)} shares…`,
      });
      const hash = await writeContractAsync({
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: 'redeem',
        args: [shares, userAddress, userAddress],
      });
      setPendingHash(hash);
      setAmount('');
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setTxState({
        status: 'error',
        message: msg.includes('User rejected') ? 'User rejected the transaction.' : msg,
      });
    }
  }

  const isDisabled = isConfirming || txState.status === 'pending';

  return (
    <div>
      <h3 className="font-semibold text-slate-700 mb-3">Redeem Shares</h3>

      {hasShares && maxShares !== undefined && (
        <p className="mb-2 text-xs text-slate-500">
          Available:{' '}
          <button
            className="underline text-blue-600 hover:text-blue-800"
            onClick={() => setAmount(formatUnits(maxShares, 18))}
          >
            {Number(formatUnits(maxShares, 18)).toLocaleString(undefined, { maximumFractionDigits: 6 })} svUSDC
          </button>
        </p>
      )}

      <div className="flex gap-2">
        <input
          type="number"
          min="0"
          step="any"
          placeholder="Shares to redeem"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <button
          onClick={() => sharesToRedeem && handleRedeem(sharesToRedeem)}
          disabled={isDisabled || !sharesToRedeem}
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
        >
          Redeem
        </button>
      </div>

      {hasShares && maxShares !== undefined && (
        <button
          onClick={() => handleRedeem(maxShares)}
          disabled={isDisabled}
          className="mt-2 w-full rounded-lg border border-blue-600 px-4 py-2 text-sm font-semibold text-blue-600 hover:bg-blue-50 disabled:opacity-50"
        >
          Redeem All
        </button>
      )}

      <TxStatus state={txState} onDismiss={() => setTxState({ status: 'idle' })} />
    </div>
  );
}
