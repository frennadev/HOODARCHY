#!/usr/bin/env node
/**
 * Re-verifies every address in src/addresses.ts against a live RPC.
 *
 * Address lists rot: proxies get upgraded, "official" docs list contracts that
 * were never deployed, and a wrong constant costs a deploy. Run this before any
 * mainnet deploy and in CI.
 *
 *   node packages/chain/scripts/verify-addresses.mjs
 *
 * Exits non-zero if anything we claim is VERIFIED has no code.
 */

const RPC = process.env.RH_MAINNET_RPC_URL ?? "https://rpc.mainnet.chain.robinhood.com";
const EXPECTED_CHAIN_ID = 4663;

/** Addresses we assert have code. Keep in sync with src/addresses.ts. */
const MUST_HAVE_CODE = {
  "WETH": "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73",
  "USDG": "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
  "MULTICALL3": "0xcA11bde05977b3631167028862bE2a173976CA11",
  "L2_MULTICALL": "0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1",
  "PERMIT2": "0x000000000022D473030F116dDEE9F6B43aC78BA3",
  "UNIV3_FACTORY": "0x1f7d7550b1b028f7571e69a784071f0205fd2efa",
  "UNIV3_SWAP_ROUTER_02": "0xcaf681a66d020601342297493863e78c959e5cb2",
  "UNIV3_UNIVERSAL_ROUTER": "0x8876789976decbfcbbbe364623c63652db8c0904",
  "UNIV3_POSITION_MANAGER": "0x73991a25c818bf1f1128deaab1492d45638de0d3",
  "UNIV3_QUOTER_V2": "0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7",
  "UNIV4_POOL_MANAGER": "0x8366a39CC670B4001A1121B8F6A443A643e40951",
  "UNIV4_POSITION_MANAGER": "0x58daec3116aae6D93017bAAea7749052E8a04fA7",
};

/**
 * Cross-checks: `to` must report `expect` when asked `sig`.
 *
 * This section exists because of a real mistake. We used to keep a list of
 * canonical v4 addresses, assert they were empty, and treat that as proof v4
 * was not deployed here. The addresses were empty and the conclusion was false —
 * v4 deploys to a different address on every chain, so absence at addresses we
 * happen to know proves nothing. Worse, the check could only ever confirm what
 * we already believed.
 *
 * Asking a contract what it is wired to can actually falsify a wrong address, so
 * that is what we do now. The v4 PositionManager naming its PoolManager, and
 * both naming the Permit2 and WETH we verified independently, is evidence a
 * codesize check cannot give us.
 */
const WIRING = [
  {
    name: "UNIV4_POSITION_MANAGER.poolManager()",
    to: "0x58daec3116aae6D93017bAAea7749052E8a04fA7",
    sig: "0xdc4c90d3", // poolManager()
    expect: "0x8366a39CC670B4001A1121B8F6A443A643e40951",
  },
  {
    name: "UNIV3_UNIVERSAL_ROUTER.poolManager()",
    to: "0x8876789976decbfcbbbe364623c63652db8c0904",
    sig: "0xdc4c90d3", // poolManager() — the router is v4-capable
    expect: "0x8366a39CC670B4001A1121B8F6A443A643e40951",
  },
];

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

const codeSize = async (addr) => ((await rpc("eth_getCode", [addr, "latest"])).length - 2) / 2;

async function main() {
  const chainId = parseInt(await rpc("eth_chainId"), 16);
  const block = parseInt(await rpc("eth_blockNumber"), 16);
  console.log(`RPC       ${RPC}`);
  console.log(`chainId   ${chainId}`);
  console.log(`block     ${block.toLocaleString()}\n`);

  if (chainId !== EXPECTED_CHAIN_ID) {
    console.error(`FAIL  expected chain ${EXPECTED_CHAIN_ID}, got ${chainId}`);
    process.exit(1);
  }

  let failures = 0;

  for (const [name, addr] of Object.entries(MUST_HAVE_CODE)) {
    const size = await codeSize(addr);
    const ok = size > 0;
    if (!ok) failures++;
    console.log(`${ok ? "ok  " : "FAIL"}  ${name.padEnd(24)} ${addr}  ${size} bytes`);
  }

  console.log("");
  for (const { name, to, sig, expect } of WIRING) {
    const raw = await rpc("eth_call", [{ to, data: sig }, "latest"]);
    const got = `0x${raw.slice(-40)}`;
    const ok = got.toLowerCase() === expect.toLowerCase();
    if (!ok) failures++;
    console.log(`${ok ? "ok  " : "FAIL"}  ${name.padEnd(38)} -> ${got}`);
    if (!ok) console.log(`      expected ${expect}`);
  }

  // Decimals are a correctness landmine; assert them explicitly.
  console.log("");
  const decimalsOf = async (addr) =>
    parseInt(await rpc("eth_call", [{ to: addr, data: "0x313ce567" }, "latest"]), 16);
  const usdgDecimals = await decimalsOf(MUST_HAVE_CODE.USDG);
  const wethDecimals = await decimalsOf(MUST_HAVE_CODE.WETH);
  const decOk = usdgDecimals === 6 && wethDecimals === 18;
  if (!decOk) failures++;
  console.log(`${decOk ? "ok  " : "FAIL"}  decimals: USDG=${usdgDecimals} (expect 6), WETH=${wethDecimals} (expect 18)`);

  console.log("");
  if (failures > 0) {
    console.error(`${failures} check(s) failed.`);
    process.exit(1);
  }
  console.log("All address checks passed.");
}

main().catch((err) => {
  console.error(`error: ${err.message}`);
  process.exit(1);
});
