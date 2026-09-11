#!/usr/bin/env node
/**
 * Checks that the contracts we have deployed still speak the ABI in this repo.
 *
 * This exists because of a real incident (D24). Adding a field to the `Proposed`
 * event changed its topic hash, and every consumer built from current ABIs went
 * blind to the deployed contract's logs. The indexer synced the whole chain,
 * matched nothing, and failed on an event for a proposal it had never seen. The
 * deployment itself kept working perfectly for anyone calling it directly, so
 * nothing surfaced the break.
 *
 * The check: read every log those addresses have emitted, and confirm each
 * topic0 is one our current ABIs can decode. An unknown topic0 means the chain
 * is emitting something this repo no longer understands — the deployment is
 * stale and anything reading it is silently broken.
 *
 *   node scripts/check-deployment-abi.mjs
 *
 * Needs RH_MAINNET_RPC_URL. Skips cleanly when it is absent, so forks and
 * secretless CI runs do not fail on something they cannot check.
 */

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { toEventSelector } from "viem";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(root, "packages/contracts/out");
const RPC = process.env.RH_MAINNET_RPC_URL;

/** Which deployed address speaks which contract's ABI. */
const DEPLOYED = {
  FutarchyGovernor: {
    dir: "FutarchyGovernor.sol",
    address: "0x1D346cd2d281bb2c07E7803Da98350ECb4e9e3eE",
  },
  ConditionalVault: {
    dir: "ConditionalVault.sol",
    address: "0xd80DF1C07252dA38C2928DD08D114BE3B92B8659",
  },
  FutarchyExecutor: {
    dir: "FutarchyExecutor.sol",
    address: "0xB469cFdf1B62f9A7dBbb562b471f9bEd982a1Feb",
  },
  MarketFactory: {
    dir: "MarketFactory.sol",
    address: "0xDfE16dDC68aFd064573C68e68163DDE2d0BbbC03",
  },
};

const START_BLOCK = 60_276_500;

let id = 0;
async function rpc(method, params = []) {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  if (!res.ok) throw new Error(`RPC ${method} -> HTTP ${res.status}`);
  const json = await res.json();
  if (json.error) throw new Error(`RPC ${method} -> ${json.error.message}`);
  return json.result;
}

/** Canonical event signature, e.g. `Proposed(bytes32,address,string,...)`. */
function signatureOf(event) {
  const types = event.inputs.map(function flatten(i) {
    if (i.type.startsWith("tuple")) {
      const suffix = i.type.slice("tuple".length);
      return `(${i.components.map(flatten).join(",")})${suffix}`;
    }
    return i.type;
  });
  return `${event.name}(${types.join(",")})`;
}

/** Ethereum uses original Keccak, not NIST SHA-3 — node's `sha3-256` would
 *  silently give a different answer, so this comes from viem. */
const topic0 = (sig) => toEventSelector(sig);

async function main() {
  if (!RPC) {
    console.log("RH_MAINNET_RPC_URL not set — skipping deployment ABI check.");
    return;
  }
  if (!existsSync(OUT)) {
    console.error("No build output. Run `forge build --root packages/contracts` first.");
    process.exit(1);
  }

  let failures = 0;

  for (const [name, { dir, address }] of Object.entries(DEPLOYED)) {
    const { abi } = JSON.parse(readFileSync(join(OUT, dir, `${name}.json`), "utf8"));

    const known = new Map();
    for (const item of abi) {
      if (item.type !== "event") continue;
      const sig = signatureOf(item);
      known.set(topic0(sig), sig);
    }

    const logs = await rpc("eth_getLogs", [
      { address, fromBlock: `0x${START_BLOCK.toString(16)}`, toBlock: "latest" },
    ]);

    const seen = new Set(logs.map((l) => l.topics[0]).filter(Boolean));
    const unknown = [...seen].filter((t) => !known.has(t));

    if (unknown.length === 0) {
      console.log(`ok    ${name.padEnd(18)} ${seen.size} event type(s) seen, all decodable`);
    } else {
      failures++;
      console.log(`FAIL  ${name.padEnd(18)} ${unknown.length} event type(s) this repo cannot decode`);
      for (const t of unknown) console.log(`        ${t}`);
      console.log(`        deployed at ${address}`);
      console.log(`        current ABI knows: ${[...known.values()].join(", ") || "(no events)"}`);
    }
  }

  console.log("");
  if (failures > 0) {
    console.error(
      "The deployed contracts emit events this repo no longer understands.\n" +
        "Either the deployment is stale and must be replaced, or an event signature\n" +
        "changed without anyone noticing. See D24 and DEPLOYMENTS.md.",
    );
    process.exit(1);
  }
  console.log("Deployed contracts still speak this repo's ABI.");
}

main().catch((err) => {
  console.error(`error: ${err.message}`);
  process.exit(1);
});
