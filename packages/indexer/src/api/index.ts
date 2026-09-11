import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { graphql } from "ponder";

/**
 * The read API. GraphQL over the indexed tables, plus a couple of endpoints for
 * the questions a frontend asks constantly and should not have to assemble.
 */
const app = new Hono();

app.use("/graphql", graphql({ db, schema }));
app.use("/", graphql({ db, schema }));

/**
 * Proposals, newest first.
 *
 * `?state=active` filters. Deliberately includes `tradingClosesAt` so a client
 * can render a countdown without a second call — that is the first thing any
 * proposal list needs and the reason the governor emits it.
 */
app.get("/proposals", async (c) => {
  const state = c.req.query("state");
  const rows = await db.select().from(schema.proposal);
  const filtered = state ? rows.filter((r) => r.state === state) : rows;
  filtered.sort((a, b) => Number(b.proposedAt - a.proposedAt));
  return c.json(filtered.map(serialise));
});

/**
 * One proposal with its markets and price history — everything a proposal page
 * renders, in one round trip.
 */
app.get("/proposals/:id", async (c) => {
  const id = c.req.param("id") as `0x${string}`;

  const [proposals, markets, observations, trades] = await Promise.all([
    db.select().from(schema.proposal),
    db.select().from(schema.market),
    db.select().from(schema.observation),
    db.select().from(schema.trade),
  ]);

  const found = proposals.find((p) => p.id.toLowerCase() === id.toLowerCase());
  if (!found) return c.json({ error: "not found" }, 404);

  const mine = <T extends { proposalId: string | null }>(rows: T[]) =>
    rows.filter((r) => r.proposalId?.toLowerCase() === id.toLowerCase());

  const series = mine(observations).sort((a, b) =>
    Number((a as { timestamp: bigint }).timestamp - (b as { timestamp: bigint }).timestamp),
  );

  return c.json({
    proposal: serialise(found),
    markets: mine(markets).map(serialise),
    // Both the slow recorded price and raw spot, so a chart can show the gap
    // between them — which is the lag visibly doing its job.
    observations: series.map(serialise),
    trades: mine(trades).map(serialise),
  });
});

/** JSON has no bigint, and silently losing precision on token amounts is worse
 *  than a string. */
function serialise<T extends Record<string, unknown>>(row: T) {
  return Object.fromEntries(
    Object.entries(row).map(([k, v]) => [k, typeof v === "bigint" ? v.toString() : v]),
  );
}

export default app;
