// Full-stack SenseLedger deployment script.
// Usage:
//   pnpm hardhat run scripts/deploy.ts --network localhost
//   pnpm hardhat run scripts/deploy.ts --network sepolia

import { ethers, network } from "hardhat";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerAddr = await deployer.getAddress();
  console.log(`Deploying to ${network.name} from ${deployerAddr}`);

  const registrarAddr = process.env.REGISTRAR_ADDRESS || deployerAddr;

  // 1. SenseToken
  const SenseToken = await ethers.getContractFactory("SenseToken");
  const token = await SenseToken.deploy(deployerAddr);
  await token.waitForDeployment();
  console.log(`SenseToken:        ${await token.getAddress()}`);

  // 2. StationNFT
  const StationNFT = await ethers.getContractFactory("StationNFT");
  const nft = await StationNFT.deploy(deployerAddr, registrarAddr);
  await nft.waitForDeployment();
  console.log(`StationNFT:        ${await nft.getAddress()}`);

  // 3. TimelockController — 1 day delay on Sepolia
  const minDelay = network.name === "sepolia" ? 60 * 60 * 24 : 60; // 1 day / 60s
  const Timelock = await ethers.getContractFactory("TimelockController");
  const timelock = await Timelock.deploy(
    minDelay,
    [],                 // proposers  (set later to DAO)
    [ethers.ZeroAddress], // executors (anyone)
    deployerAddr,       // admin (revoked at end)
  );
  await timelock.waitForDeployment();
  console.log(`TimelockController: ${await timelock.getAddress()}`);

  // 4. SenseDAO
  const SenseDAO = await ethers.getContractFactory("SenseDAO");
  const dao = await SenseDAO.deploy(await token.getAddress(), await timelock.getAddress());
  await dao.waitForDeployment();
  console.log(`SenseDAO:          ${await dao.getAddress()}`);

  // 5. RewardDistributor
  const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
  const distributor = await RewardDistributor.deploy(
    await token.getAddress(),
    deployerAddr,   // admin
    deployerAddr,   // publisher (the wallet-bridge takes this over later)
  );
  await distributor.waitForDeployment();
  console.log(`RewardDistributor: ${await distributor.getAddress()}`);

  // 6. Role wiring
  const MINTER_ROLE = await token.MINTER_ROLE();
  await (await token.grantRole(MINTER_ROLE, await distributor.getAddress())).wait();
  console.log("Granted MINTER_ROLE on SenseToken to RewardDistributor");

  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();
  const TIMELOCK_ADMIN_ROLE = await timelock.DEFAULT_ADMIN_ROLE();
  await (await timelock.grantRole(PROPOSER_ROLE, await dao.getAddress())).wait();
  await (await timelock.grantRole(CANCELLER_ROLE, await dao.getAddress())).wait();
  // Renounce deployer admin on timelock so only the DAO governs it.
  await (await timelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployerAddr)).wait();
  console.log("Timelock: proposer/canceller → DAO; admin renounced");

  // 7. Persist addresses
  const out = {
    network: network.name,
    chainId: (await ethers.provider.getNetwork()).chainId.toString(),
    deployer: deployerAddr,
    addresses: {
      SenseToken:         await token.getAddress(),
      StationNFT:         await nft.getAddress(),
      TimelockController: await timelock.getAddress(),
      SenseDAO:           await dao.getAddress(),
      RewardDistributor:  await distributor.getAddress(),
    },
    deployedAt: new Date().toISOString(),
  };

  const dir = join(__dirname, "..", "deployments");
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `${network.name}.json`);
  writeFileSync(file, JSON.stringify(out, null, 2));
  console.log(`Wrote ${file}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
