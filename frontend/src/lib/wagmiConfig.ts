import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia } from 'wagmi/chains';

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? '';
const sepoliaRpc = process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL;

export const wagmiConfig = getDefaultConfig({
  appName: 'ERC-4626 Vault Demo',
  projectId,
  chains: [
    {
      ...sepolia,
      rpcUrls: sepoliaRpc
        ? { default: { http: [sepoliaRpc] } }
        : sepolia.rpcUrls,
    },
  ],
  ssr: true,
});
