# Blockchain / Ethereum / DAO Roadmap

> Intermediate, hands-on. Assumes you know what a public/private keypair is and have used a block explorer. Goal: ship the SenseLedger on-chain stack — SENSE ERC-20 token, Station NFT, SenseDAO governance — on Sepolia, with tests, audits of your own code, and a Foundry/Hardhat workflow you'd recognize at a real protocol team.

## Mental model first

1. **Smart contracts are small, adversarial, append-mostly programs.** You write 200 lines of Solidity that will outlive everything you've ever built and handle money you don't own. Act like it.
2. **Gas is the cost function for every design choice.** Storage is expensive, computation is cheap, calldata is somewhere in between. Packing matters.
3. **Composability is the point.** You're not building an island — the ERC standards, ABI, and function signatures let your contracts plug into everything else on-chain.
4. **There is no "update and redeploy."** Upgrades are a deliberate mechanism (proxies) with their own failure modes. Most contracts should not be upgradeable.
5. **Off-chain is where you live.** Most of the work is off-chain: indexers, event listeners, oracles, signed messages, merkle proofs. Learn the on-chain/off-chain seam.
6. **You will be attacked.** Reentrancy, front-running, oracle manipulation, access control bugs, integer edge cases, signature replay, phishing your own users. Every mistake has a name and a postmortem.

## Core surface area

| Area | What to know |
|------|--------------|
| EVM | Accounts, transactions, gas, storage vs memory vs calldata, events, logs, the stack, selectors |
| Solidity | `^0.8.x` basics, visibility, modifiers, errors (custom), events, interfaces, abstract contracts, assembly (read-only) |
| Standards | ERC-20, ERC-721, ERC-1155, ERC-712 (typed signatures), ERC-2612 (permit), ERC-4337 (AA, optional), ERC-1967 (proxy storage) |
| Libraries | OpenZeppelin Contracts — know what's in there. Don't reinvent `Ownable`, `ReentrancyGuard`, `AccessControl`, `ECDSA`, `MerkleProof`. |
| Tooling | Foundry (`forge`, `cast`, `anvil`) *or* Hardhat. Foundry is faster and Solidity-native; Hardhat has more plugins and a JS ecosystem. Learn one deeply. |
| Testing | Unit tests, fuzzing (Foundry fuzz), invariant testing, fork tests (mainnet state) |
| Security | Reentrancy, checks-effects-interactions, pull-over-push, access control, signature replay, front-running / MEV, oracle attacks, upgrade bricking |
| Deployment | Deterministic deploy (CREATE2), deployment scripts, verification on Etherscan, multi-network config |
| Infra | RPC providers (Alchemy, Infura, QuickNode), indexers (The Graph, Ponder), paymasters (for gasless UX) |
| DAO | Governor pattern (OZ Governor), timelock, voting power (ERC-20Votes / ERC-721Votes), snapshots, off-chain voting (Snapshot) vs on-chain |

## Scenarios

Pick **Foundry** if you want speed and raw Solidity. Pick **Hardhat** if you want a JS/TS-heavy workflow that plays nicely with your frontend. This roadmap uses **Hardhat + ethers v6** as the default (see `projects/blockchain/`) to keep the TypeScript stack unified with the mobile app. Swap to Foundry if you prefer.

### Scenario 1 — Local dev environment and the first ERC-20

- Install Node LTS + Hardhat. Scaffold `projects/blockchain/` (already started — you'll fill it in).
- Pull in OpenZeppelin Contracts.
- Write `SenseToken.sol`: ERC-20 with `mint` restricted to a `MINTER_ROLE`, `ERC20Votes` mixed in for future governance.
- Tests for: initial supply zero, mint happy path, mint access control, total supply math, voting power snapshot.
- Run the test suite. Run it under gas reporting (`REPORT_GAS=1`).
- **Exit criteria**: Green tests, understood gas numbers per function, local anvil/hardhat node running.

### Scenario 2 — Station NFT

- Write `StationNFT.sol`: ERC-721 minted one-per-device when a station is first registered on-chain. Token ID = `uint256(keccak256(deviceFingerprint))`.
- Include `ERC721URIStorage` for metadata (we'll host metadata off-chain for now).
- Add an `onlyRegistrar` modifier — only the backend's registrar address can mint.
- Tests: mint, duplicate mint reverts, transfer, metadata.
- **Exit criteria**: You can mint a Station NFT from a script; the ID is deterministic; no one else can mint.

### Scenario 3 — Reward distribution via merkle roots

This is the core of SenseLedger's on-chain economics. Don't mint per-reading — that's gas suicide.

- Design: each hour, the backend produces a merkle root of `(address, amount)` reward pairs. It publishes the root on-chain via a `RewardDistributor.sol` contract. Users claim by submitting a merkle proof.
- Write `RewardDistributor.sol`: `postRoot(bytes32 root, uint256 epoch)`, `claim(uint256 epoch, uint256 amount, bytes32[] proof)`. Use OZ's `MerkleProof`.
- Off-chain: write a TypeScript script that takes a JSON file of `{address, amount}` and produces root + proofs.
- Tests: valid claim, invalid proof reverts, double-claim reverts, unknown epoch reverts, claim across multiple epochs.
- Fuzz test: given N random recipients, every valid claim succeeds, every invalid claim fails.
- **Exit criteria**: You can post a merkle root, claim for 3 addresses, and deny a fake one. Gas per claim < 80k.

### Scenario 4 — SenseDAO governance

- Use OpenZeppelin's `Governor` contracts (Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl).
- Voting power = SENSE balance snapshot at proposal start (via ERC20Votes).
- Timelock of 24h on Sepolia (2 days on "mainnet" in the config).
- Initial proposals should include: "change reward per verified reading", "change quality threshold", "upgrade validation rules address".
- Write `SenseDAO.sol` (subclass of Governor wiring all of the above).
- Tests: propose → vote → queue → execute full path, quorum failure, timelock respected, unauthorized execute reverts.
- **Exit criteria**: End-to-end proposal lifecycle works in a test. Voting power uses snapshots, not live balances.

### Scenario 5 — The wallet bridge (off-chain ↔ on-chain)

This is the trickiest piece architecturally.

- The backend (on k8s) has a `wallet-bridge` service holding a hot wallet with `MINTER_ROLE` and `REGISTRAR_ROLE`.
- Keys stored via External Secrets Operator pulling from a secret manager (Vault, cloud secret manager, or for learning: a sealed secret).
- Responsibilities:
  - Register stations (mint NFTs) when a device onboards.
  - Publish hourly merkle roots to `RewardDistributor`.
  - Listen to on-chain events and feed them back to the API (e.g., a DAO vote result triggering a validation-config change).
- Gas strategy: EIP-1559 with dynamic fee cap; fallback to legacy if the network doesn't support it; circuit breaker if gas exceeds a threshold.
- **Exit criteria**: Bridge reliably posts roots every hour, recovers from chain reorgs, survives wallet nonce gaps.

### Scenario 6 — Indexing and off-chain read path

- Option A: Use **The Graph** — write a subgraph mapping SENSE transfers, NFT mints, and DAO events into a GraphQL schema.
- Option B: Use **Ponder** (TypeScript, simpler) if you don't want to touch AssemblyScript.
- The mobile app and ingest API query the indexer, not the chain directly. Direct RPC calls from the app will be slow and rate-limited.
- **Exit criteria**: Mobile app gets its balance history from the indexer in < 200ms p95.

### Scenario 7 — Security review and fuzzing

- Run Slither across the contracts. Read and address every finding. Ignore none without a written justification.
- Run Mythril or MythX on the top-risk contracts.
- Write invariant tests (Foundry's `invariant_` or Echidna):
  - Total supply never exceeds `MAX_SUPPLY`.
  - Sum of claimed rewards per epoch <= total rewards for that epoch.
  - Every Station NFT has exactly one owner.
- Document known limitations in `SECURITY.md` inside `projects/blockchain/`.
- **Exit criteria**: Zero `high` or `critical` findings; all `medium` findings documented or fixed.

### Scenario 8 — Deploy, verify, and operate on Sepolia

- Set up `.env` for network / RPC / deployer key (testnet key, never reuse).
- Write deployment scripts (`scripts/deploy.ts`) that deploy in order: Token → NFT → Distributor → Timelock → Governor → wire roles → transfer ownership to DAO.
- Verify each contract on Etherscan (`hardhat verify`).
- Run a real end-to-end test on Sepolia: mint a test Station, post a test merkle root, claim from a test account, propose and execute a trivial DAO action.
- Write a runbook in `projects/blockchain/RUNBOOK.md` for: how to deploy, how to rotate the bridge wallet, how to respond to an incident.
- **Exit criteria**: All contracts live and verified on Sepolia. Real claim and real DAO vote executed on-chain.

## Where this feeds SenseLedger

| Blockchain deliverable | SenseLedger piece |
|------------------------|-------------------|
| Scenario 1 | SENSE token used for rewards and governance voting power |
| Scenario 2 | Station NFT proves a device is legitimately registered |
| Scenario 3 | Hourly reward payouts for verified contributions |
| Scenario 4 | DAO controls validation config (quality threshold, reward rate) |
| Scenario 5 | Wallet bridge is the seam between the k8s backend and the chain |
| Scenario 6 | Mobile app reads balances and history without hammering RPC |

## Resources

- `docs.soliditylang.org`
- `docs.openzeppelin.com/contracts` — read every contract you plan to inherit from
- `book.getfoundry.sh` (Foundry) or `hardhat.org/docs` (Hardhat)
- `ethereum.org/en/developers` — canonical concept reference
- `consensys.github.io/smart-contract-best-practices/`
- `github.com/crytic/slither`
- `thegraph.com/docs` or `ponder.sh`
- `chain.link/education` — oracle concepts
- `www.rareskills.io` blog — strong intermediate Solidity content
- Past exploits as reading: `rekt.news`, `github.com/SunWeb3Sec/DeFiHackLabs` — learn from others' disasters

## Anti-patterns to avoid

- **`tx.origin` for auth.** Use `msg.sender`.
- **Loops over unbounded arrays.** O(n) storage reads DoS your contract.
- **Using `block.timestamp` as randomness.** It's manipulable.
- **`transfer` / `send` to arbitrary addresses.** Use `call` with explicit gas and check the return value.
- **Upgradeable by default.** Default to immutable; make upgradeability an explicit, boxed-in decision.
- **`onlyOwner` on everything.** Use roles (`AccessControl`) and transfer the role set to the DAO or a multisig.
- **Trusting off-chain data without signatures.** If the backend says "mint X to Y," the contract must verify a signature from a known authority.
- **Testing only the happy path.** Every `require` / custom error should have a revert test.

## Done when

- All contracts deployed and verified on Sepolia, owned by the SenseDAO + timelock (not by an EOA).
- You've done one end-to-end run: station registered → readings submitted → merkle root posted → user claims SENSE → user votes in DAO → DAO changes a parameter → backend reacts.
- Slither + your own fuzz suite are green.
- You can explain, in front of a whiteboard, where the money moves and who can do what. Without looking at the code.
