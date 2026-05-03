// Off-chain merkle root + proof generator for the RewardDistributor.
//
// The on-chain leaf schema is:
//   keccak256(bytes.concat(
//     bytes32(index),
//     bytes32(uint256(uint160(account))),
//     bytes32(amount)
//   ))
//
// This script takes a recipients JSON file like:
//   [{ "account": "0x...", "amount": "1000000000000000000" }, ...]
// and prints the root + per-leaf proofs.
//
// Usage:
//   pnpm ts-node scripts/merkle.ts ./fixtures/epoch-42.json

import { readFileSync, writeFileSync } from "node:fs";
import { keccak256, getBytes, AbiCoder, concat, toBeHex } from "ethers";

type Recipient = { account: string; amount: string };

interface Leaf {
  index: number;
  account: string;
  amount: string;
  hash: string;
}

function leafHash(index: number, account: string, amount: string): string {
  const packed = concat([
    toBeHex(index, 32),
    toBeHex(BigInt(account), 32),
    toBeHex(BigInt(amount), 32),
  ]);
  return keccak256(packed);
}

function buildTree(leaves: Leaf[]): string[][] {
  const layers: string[][] = [leaves.map((l) => l.hash)];
  while (layers[layers.length - 1].length > 1) {
    const prev = layers[layers.length - 1];
    const next: string[] = [];
    for (let i = 0; i < prev.length; i += 2) {
      const left = prev[i];
      const right = i + 1 < prev.length ? prev[i + 1] : left; // duplicate last if odd
      // Sort the pair so proofs don't need to encode left/right.
      const [a, b] = left < right ? [left, right] : [right, left];
      next.push(keccak256(concat([a, b])));
    }
    layers.push(next);
  }
  return layers;
}

function proofForIndex(layers: string[][], index: number): string[] {
  const proof: string[] = [];
  let i = index;
  for (let l = 0; l < layers.length - 1; l++) {
    const layer = layers[l];
    const sibling = i % 2 === 0 ? i + 1 : i - 1;
    proof.push(sibling < layer.length ? layer[sibling] : layer[i]);
    i = Math.floor(i / 2);
  }
  return proof;
}

function main() {
  const [inputFile] = process.argv.slice(2);
  if (!inputFile) {
    console.error("usage: ts-node scripts/merkle.ts <recipients.json>");
    process.exit(1);
  }
  const recipients: Recipient[] = JSON.parse(readFileSync(inputFile, "utf8"));
  const leaves: Leaf[] = recipients.map((r, i) => ({
    index: i,
    account: r.account,
    amount: r.amount,
    hash: leafHash(i, r.account, r.amount),
  }));

  const layers = buildTree(leaves);
  const root = layers[layers.length - 1][0];
  const totalAmount = recipients
    .reduce((acc, r) => acc + BigInt(r.amount), 0n)
    .toString();

  const output = {
    root,
    totalAmount,
    leaves: leaves.map((l) => ({
      index: l.index,
      account: l.account,
      amount: l.amount,
      proof: proofForIndex(layers, l.index),
    })),
  };

  const outFile = inputFile.replace(/\.json$/, ".merkle.json");
  writeFileSync(outFile, JSON.stringify(output, null, 2));
  console.log(`root:        ${root}`);
  console.log(`total:       ${totalAmount}`);
  console.log(`recipients:  ${recipients.length}`);
  console.log(`wrote:       ${outFile}`);
}

main();
