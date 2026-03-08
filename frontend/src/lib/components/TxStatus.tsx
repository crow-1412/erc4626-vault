'use client';

type TxState =
  | { status: 'idle' }
  | { status: 'pending'; description: string }
  | { status: 'success'; hash: string }
  | { status: 'error'; message: string };

interface TxStatusProps {
  state: TxState;
  onDismiss: () => void;
}

export function TxStatus({ state, onDismiss }: TxStatusProps) {
  if (state.status === 'idle') return null;

  const bannerClass =
    state.status === 'pending'
      ? 'bg-yellow-50 border-yellow-300 text-yellow-800'
      : state.status === 'success'
        ? 'bg-green-50 border-green-300 text-green-800'
        : 'bg-red-50 border-red-300 text-red-800';

  return (
    <div className={`mt-4 rounded-lg border p-3 text-sm ${bannerClass}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1">
          {state.status === 'pending' && (
            <p>
              <span className="font-semibold">Pending:</span> {state.description}
            </p>
          )}
          {state.status === 'success' && (
            <p>
              <span className="font-semibold">Success!</span>{' '}
              <a
                href={`https://sepolia.etherscan.io/tx/${state.hash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="underline"
              >
                View on Etherscan
              </a>
            </p>
          )}
          {state.status === 'error' && (
            <p>
              <span className="font-semibold">Error:</span> {state.message}
            </p>
          )}
        </div>
        {state.status !== 'pending' && (
          <button
            onClick={onDismiss}
            className="ml-2 text-lg leading-none opacity-60 hover:opacity-100"
            aria-label="Dismiss"
          >
            ×
          </button>
        )}
      </div>
    </div>
  );
}

export type { TxState };
