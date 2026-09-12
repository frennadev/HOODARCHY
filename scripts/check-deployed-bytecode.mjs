#!/usr/bin/env node
/**
 * Is the code running on chain still the code in this repo?
 *
 * The ABI check answers a narrower question — whether we can still *decode* what
 * a deployment emits. It would happily pass against a contract whose internals
 * were rewritten, as long as the event signatures matched. This compares the
 * actual runtime bytecode.
 *
 * Immutables are the wrinkle: they are baked into the deployed code but appear
 * as zero placeholders in the compiled artifact, so a naive comparison always
 * fails. Solidity records exactly where they sit, so both sides are masked at
 * those offsets and everything else must match byte for byte.
 *
 *   node scripts/check-deployed-bytecode.mjs
 *
 * Needs RH_MAINNET_RPC_URL. Skips cleanly without it.
 */

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(root, "packages/contracts/out");
const RPC = process.env.RH_MAINNET_RPC_URL;

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
  ConditionalAmm: {
    dir: "ConditionalAmm.sol",
    address: "0x1DFC1648598182a07e75bD3966d7AE7Cf3f9eC0f", // the live pass market
  },
  LaggedTwapOracle: {
    dir: "LaggedTwapOracle.sol",
    address: "0x0047779d0a869B2C6602c3Bf54042E6f7C916C21", // the live pass oracle
  },
};

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

/** Zero out the byte ranges Solidity reserved for immutables. */
function mask(bytes, immutableReferences) {
  const out = Buffer.from(bytes);
  for (const refs of Object.values(immutableReferences ?? {})) {
    for (const { start, length } of refs) out.fill(0, start, start + length);
  }
  return out;
}

async function main() {
  if (!RPC) {
    console.log("RH_MAINNET_RPC_URL not set — skipping bytecode check.");
    return;
  }
  if (!existsSync(OUT)) {
    console.error("No build output. Run `forge build --root packages/contracts` first.");
    process.exit(1);
  }

  let drifted = 0;

  for (const [name, { dir, address }] of Object.entries(DEPLOYED)) {
    const artifact = JSON.parse(readFileSync(join(OUT, dir, `${name}.json`), "utf8"));
    const expectedHex = artifact.deployedBytecode.object.replace(/^0x/, "");
    const immutables = artifact.deployedBytecode.immutableReferences;

    const onChainHex = (await rpc("eth_getCode", [address, "latest"])).replace(/^0x/, "");

    const expected = mask(Buffer.from(expectedHex, "hex"), immutables);
    const onChain = mask(Buffer.from(onChainHex, "hex"), immutables);

    const immCount = Object.values(immutables ?? {}).flat().length;
    const label = `${name} (${immCount} immutable${immCount === 1 ? "" : "s"} masked)`;

    if (expected.length !== onChain.length) {
      drifted++;
      console.log(`DRIFT ${label.padEnd(46)} length ${onChain.length} on chain vs ${expected.length} local`);
      continue;
    }
    if (expected.equals(onChain)) {
      console.log(`same  ${label.padEnd(46)} ${onChain.length} bytes`);
    } else {
      drifted++;
      let first = 0;
      while (first < expected.length && expected[first] === onChain[first]) first++;
      console.log(`DRIFT ${label.padEnd(46)} first differing byte at offset ${first}`);
    }
  }

  console.log("");
  if (drifted > 0) {
    console.log(
      `${drifted} contract(s) differ from this repo's build.\n` +
        "The deployment no longer runs the code here. Redeploy, or record which\n" +
        "commit it corresponds to in DEPLOYMENTS.md.",
    );
    process.exit(1);
  }
  console.log("Every deployed contract still matches this repo's build.");
}

main().catch((err) => {
  console.error(`error: ${err.message}`);
  process.exit(1);
});
