/**
 * Everything a consumer needs to talk to this system: network definitions,
 * verified ecosystem addresses, our own deployments, and the contract ABIs.
 *
 * The frontend and indexer both import from here rather than reaching into
 * Foundry's `out/` directory, which is gitignored and would be missing on a
 * fresh clone.
 */
export * from "./chains.js";
export * from "./addresses.js";
export * from "./deployments.js";
export * from "./abis/index.js";
