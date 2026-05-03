# Blockchain — SenseLedger Hands-On

Scaffold for the blockchain roadmap. A Hardhat + TypeScript workspace with
OpenZeppelin primitives. Swap for Foundry if you prefer — the contracts port
cleanly.

## What's here

```
blockchain/
├── README.md               ← you are here
├── package.json            ← hardhat + OZ + ethers v6 + TS
├── hardhat.config.ts       ← networks, accounts, gas reporter, verify
├── tsconfig.json
├── .env.example            ← copy to .env and fill in for Sepolia deploys
├── .gitignore              ← node_modules, artifacts, cache, .env
├── contracts/
│   ├── SenseToken.sol      ← ERC-20 with ERC20Votes and MINTER_ROLE
│   ├── StationNFT.sol      ← ERC-721 minted per registered device
│   ├── RewardDistributor.sol ← merkle-root claim pattern
│   └── SenseDAO.sol        ← OZ Governor + Timelock (stubbed)
├── scripts/
│   ├── deploy.ts           ← full-stack deployment
│   └── merkle.ts           ← off-chain merkle root + proof builder
└── test/
    ├── SenseToken.test.ts
    ├── StationNFT.test.ts
    └── RewardDistributor.test.ts
```

## Prerequisites

- Node LTS (20+)
- `pnpm` or `npm`
- A Sepolia ETH balance on your test wallet (faucet)
- An Alchemy / Infura RPC key for Sepolia (for `hardhat verify`)
- Etherscan API key (for contract verification)

## Quickstart

```bash
# 1. Install
pnpm install     # or npm install

# 2. Compile
pnpm hardhat compile

# 3. Run unit tests
pnpm hardhat test

# 4. Start a local node (separate terminal)
pnpm hardhat node

# 5. Deploy to local node
pnpm hardhat run scripts/deploy.ts --network localhost

# 6. Deploy to Sepolia (requires .env)
pnpm hardhat run scripts/deploy.ts --network sepolia
```

## Security-first workflow

Before you deploy anything to Sepolia:

```bash
# Static analysis
pip install slither-analyzer
slither .

# Gas report (helps you spot unexpected growth)
REPORT_GAS=true pnpm hardhat test

# Coverage
pnpm hardhat coverage
```

## Deploy order

Contracts must be deployed in this order because later contracts reference
earlier ones:

1. `SenseToken` (ERC-20 + ERC20Votes)
2. `StationNFT` (ERC-721)
3. `TimelockController` (OZ)
4. `SenseDAO` (Governor wired to token + timelock)
5. `RewardDistributor` (references SenseToken)
6. Role setup:
   - Grant `MINTER_ROLE` on `SenseToken` to `RewardDistributor` (for claims)
   - Grant `REGISTRAR_ROLE` on `StationNFT` to the backend wallet bridge address
   - Transfer ownership of `RewardDistributor.postRoot` to the backend wallet bridge
   - Transfer admin roles to the `TimelockController` (so the DAO owns them)
7. Verify all contracts on Etherscan
8. Write the deployed addresses to `deployments/sepolia.json`

`scripts/deploy.ts` handles all of this.

## Integration with the rest of SenseLedger

- The backend `wallet-bridge` service (on k8s) reads `deployments/sepolia.json`
  to know contract addresses. Commit this file (testnet only!).
- The mobile app reads the same file (or an injected env) to know where to
  point its WalletConnect / ethers calls.
- The indexer (The Graph or Ponder) also needs the addresses.

## What you should *not* do here

- Don't deploy to mainnet. Ever. This is a learning project.
- Don't commit a `.env` with a real private key. The `.gitignore` exists for a reason, but trust-no-commit.
- Don't re-use a private key across multiple projects.
- Don't skip the Slither run. Every contract in `contracts/` must be clean or documented.
