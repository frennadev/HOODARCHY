#!/usr/bin/env node
/**
 * Checks that every relative link and anchor in docs/ resolves.
 *
 * These docs are published, cross-reference each other heavily, and get
 * renamed during editing. A broken link is the cheapest possible thing to
 * catch automatically, so catch it automatically.
 *
 *   node scripts/check-docs-links.mjs
 */

import { readdir, readFile } from "node:fs/promises";
import { join, dirname, resolve, relative } from "node:path";
import { existsSync } from "node:fs";

const DOCS = resolve(import.meta.dirname, "..", "docs");

/** GitHub-style anchor slug. */
const slug = (heading) =>
  heading
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");

const files = (await readdir(DOCS)).filter((f) => f.endsWith(".md"));

// Collect every heading so we can validate #anchors too.
const anchors = new Map();
for (const f of files) {
  const body = await readFile(join(DOCS, f), "utf8");
  const found = [...body.matchAll(/^#{1,6}\s+(.+)$/gm)].map((m) => slug(m[1]));
  anchors.set(f, new Set(found));
}

const LINK = /\[([^\]]*)\]\(([^)]+)\)/g;
let broken = 0;
let checked = 0;

for (const f of files) {
  const body = await readFile(join(DOCS, f), "utf8");

  for (const [, text, href] of body.matchAll(LINK)) {
    if (/^(https?:|mailto:)/.test(href)) continue; // external, not our problem
    checked++;

    const [path, anchor] = href.split("#");

    // Pure in-page anchor.
    if (!path) {
      if (anchor && !anchors.get(f).has(anchor)) {
        console.log(`BROKEN  ${f}: "${text}" -> #${anchor} (no such heading)`);
        broken++;
      }
      continue;
    }

    const target = resolve(dirname(join(DOCS, f)), path);
    if (!existsSync(target)) {
      console.log(`BROKEN  ${f}: "${text}" -> ${path} (file not found)`);
      broken++;
      continue;
    }

    const targetName = relative(DOCS, target);
    if (anchor && anchors.has(targetName) && !anchors.get(targetName).has(anchor)) {
      console.log(`BROKEN  ${f}: "${text}" -> ${path}#${anchor} (no such heading)`);
      broken++;
    }
  }
}

console.log(`\n${files.length} files, ${checked} internal links checked.`);
if (broken > 0) {
  console.error(`${broken} broken.`);
  process.exit(1);
}
console.log("All internal links resolve.");
