'use client';

import { useState, useEffect } from 'react';
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, maxUint256 } from 'viem';
import { VAULT_ADDRESS, USDC_ADDRESS, VAULT_ABI, ERC20_ABI } from '@/lib/contracts';
import { TxStatus, type TxState } from './TxStatus';
import type { Address } from 'viem';

interface DepositFormProps {
  userAddress: Address;
}

export function DepositForm({ userAddress }: DepositFormProps) {
  const [amount, setAmount] = useState('');
  const [txState, setTxState] = useState<TxState>({ status: 'idle' });

  // Parse input as mUSDC (6 decimals)
  const amountBn = (() => {
    try {
      const n = parseFloat(amount);
      if (!amount || isNaN(n) || n <= 0) return undefined;
      return parseUnits(amount, 6);
    } catch {
      return undefined;
    }
  })();

  // Read allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: USDC_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [userAddress, VAULT_ADDRESS],
    query: { refetchInterval: 6000 },
  });

  const needsApproval = amountBn !== undefined && (allowance === undefined || allowance < amountBn);

  // Write hooks
  const { writeContractAsync } = useWriteContract();
  const [pendingHash, setPendingHash] = useState<`0x${string}` | undefined>();

  const { isLoading: isConfirming, isSuccess: isConfirmed, data: receipt } =
    useWaitForTransactionReceipt({ hash: pendingHash });

  useEffect(() => {
    if (isConfirmed && receipt) {
      setTxState({ status: 'success', hash: receipt.transactionHash });
      setPendingHash(undefined);
      refetchAllowance();
    }
  }, [isConfirmed, receipt, refetchAllowance]);

  async function handleApprove() {
    if (!amountBn) return;
    try {
      setTxState({ status: 'pending', description: 'Approving mUSDC spend…' });
      const hash = await writeContractAsync({
        address: USDC_ADDRESS,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [VAULT_ADDRESS, maxUint256],
      });
      setPendingHash(hash);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setTxState({
        status: 'error',
        message: msg.includes('User rejected') ? 'User rejected the transaction.' : msg,
      });
    }
  }

  async function handleDeposit() {
    if (!amountBn) return;
    try {
      setTxState({ status: 'pending', description: `Depositing ${amount} mUSDC…` });
      const hash = await writeContractAsync({
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: 'deposit',
        args: [amountBn, userAddress],
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

  const isDisabled = !amountBn || isConfirming || txState.status === 'pending';

  return (
    <div>
      <h3 className="font-semibold text-slate-700 mb-3">Deposit mUSDC</h3>
      <div className="flex gap-2">
        <input
          type="number"
          min="0"
          step="any"
          placeholder="Amount (mUSDC)"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        {needsApproval ? (
          <button
            onClick={handleApprove}
            disabled={isDisabled}
            className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-600 disabled:opacity-50"
          >
            Approve
          </button>
        ) : (
          <button
            onClick={handleDeposit}
            disabled={isDisabled}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Deposit
          </button>
        )}
      </div>
      {needsApproval && amountBn && (
        <p className="mt-1 text-xs text-amber-600">Approve mUSDC spend before depositing.</p>
      )}
      <TxStatus state={txState} onDismiss={() => setTxState({ status: 'idle' })} />
    </div>
  );
}
