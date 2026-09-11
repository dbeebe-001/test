# CLAUDE.md — Ramp-quote workspace (laulima26, cloud session)

Revenue Cloud ramp-quote demos on **laulima26**, running conversationally from a Claude Code
on the web session. This repo root stands in for the `demos/native/` **and** `demos/cohort/`
folders in [bgaldino/ramp-demo-kit](https://github.com/bgaldino/ramp-demo-kit) combined — a
`SessionStart` hook (`.claude/hooks/session-start.sh`) clones that kit into the container,
mints an MCP access token, and writes `.mcp.json` at this repo's root automatically at session
start. The one `revenue-cloud` connector multiplexes both the standard `industries/revenue-cloud`
server (cohort lines, `soqlQuery`, `createSalesTransaction`) and the custom `rampdealsconnect`
server (native groups, `placeSalesTransaction`/`cloneSalesTransaction`) — everything below is
reachable from this one session.

**MCP connector prerequisite:** this only works if the `RAMP_SF_CSEC` environment variable
(the ECA's consumer secret) is configured in this environment's settings on claude.ai/code.
Run `/mcp` — it should show `revenue-cloud` Connected. If it isn't, the hook's stderr output
(visible in session startup logs) will say why — almost always a missing/wrong `RAMP_SF_CSEC`.

## Which model to build

Both models answer the same prompt:

> **Read the Momentum Call note for Acme account and build the ramp quotes for review.**

- **No model named → build NATIVE** (the default; group-ramp segments via
  `placeSalesTransaction`/`cloneSalesTransaction`).
- **"cohort", "cohort model", "flat co-terming lines", "cohort lines" → build COHORT**
  instead (`createSalesTransaction` with inline per-year cohort lines).
- **"both models", "compare native and cohort", "show the contrast" → build BOTH**: run the
  native pair and the cohort pair (four quotes total), then present all four with one closing
  paragraph on *why* the totals differ (native reprices a growing active base; cohort prices
  each year's new cohort separately — see each section's shape caveat). Reuse each section's
  own presentation format for its two quotes; add one short comparison line at the very end,
  not a rebuilt table.

Everything else — accounts, ids, discount policy, "how to talk" — is per-model, in its own
section below.

---

## Native model — QuoteLineGroup ramps

Native-groups ramp demo: `placeSalesTransaction` → `EditGroup` → `cloneSalesTransaction`, the
`QuoteLineGroup` segment shape. On the prompt, **always run the parallel build below** — it is
the default path, not an option. Read `MomentumCallNotes__c` for Acme, interpret the deal, then
build both quotes via two concurrent subagents. No exploration, no existence checks, no catalog
lookups — everything is pre-resolved.

### Two modes — FLAT (default) vs FAITHFUL

The plain prompt builds **FLAT** (fast, level segments — see the shape caveat). To build the
**FAITHFUL** ramp (each year's real user growth + discount ladder from the note), the prompt names it:

> **…build the ramp quotes *faithfully* (full user growth + discount ladder) for review.**

Trigger words = **faithful**, **full ramp**, **with the discounts**, **match the note's economics**,
**per-year growth**. Any of these → faithful mode; otherwise → flat. Faithful runs the same parallel
build **plus a batched post-clone reprice** (step 4b: one SOQL + one PATCH graph for all later
segments), so it is a little slower. Everything else — accounts, ids, transport, presentation — is identical.

### Two hard build rules (keep it fast, keep clone working)

- `taxPref:"Skip"` **on EVERY** `placeSalesTransaction` **call** → the quote settles synchronously to
`CompletedWithPricing`. Without it you get async `CompletedWithTax` and feel you must poll.
- **Never poll** `CalculationStatus`**.** Each call returns already settled; the next runs immediately.
Only read status if a clone *errors* (`SaveFailedOrIncomplete`/`ProductDetailsNotFound` = wrong PBE).

### Shape caveat — FLAT vs FAITHFUL economics

The note describes per-year quantity growth **+ a discount ladder**, co-terming. The two modes render
that differently — say which one you built, plainly, and never pretend the native TCV matches the note:

- **FLAT (default):** `cloneSalesTransaction` copies the prior segment **as-is** (same qty, same
discount) into sequential 12-month segments — so the quotes show the ramp **SHAPE** (segments,
`IsRamped`, per-line `RampIdentifier`) at level economics. **Native flat TCV ≠ cohort TCV**
($282,500 / $237,500) — that mismatch is expected.
- **FAITHFUL:** after the clone chain, each later segment is repriced (step 4b) to the note's
**cumulative-active** headcount and that year's discount. Native segments hold cumulative-active
users (base + adds×(year−1)), **not** the cohort's per-year incremental cohorts — so the faithful
native TCV *also* won't equal the cohort TCV, and that's the honest native representation. State it
as: "native models the ramp as a growing active base; the cohort model prices each year's new
cohort separately, so the totals differ."

### Pre-resolved ids — `laulima26` (native)

**Verified 2026-08-06** — full place→EditGroup→clone×N→faithful-reprice chain, both ramp lengths,
live. 3-yr: quote `0Q0Ws000009RgZ3KAK`, 3 segments / 3 lines, TCV $267,474.17, 72s. 4-yr:
`0Q0Ws000009RdPuKAK`, 4 segments / 4 lines, $224,986.23, 52s. Both `CompletedWithPricing`, one
`RampIdentifier` per quote with a distinct `SegmentIdentifier` per segment. Re-resolved and
re-verified from a cloud session on 2026-09-09 (script run, not conversational): 3-yr quote
`0Q0Ws000009r7HVKAY`, TCV $267,474.17, 70.2s — same shape, confirming the org and connector are
live and correct.

⚠ Segment EndDate must be exactly 1 day short of the calendar anniversary. A "Yearly" segment with StartDate 2026-10-01 needs EndDate 2027-09-30 — not 2027-10-01. Using the exact anniversary date fails EditGroup validation (a Yearly segment must be under, not exactly, 365/366 days). This applies to every segment's StartDate/EndDate pair in steps 1 and 3, and this primer's own literal JSON already gets it right — don't "fix" the dates to look like clean anniversaries when adapting the graph for a different start date or ramp length.

| Thing                                      | id                                        | Notes                                                                                                                             |
| ------------------------------------------ | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Acme account                               | `001Ws00005vw5s0IAA`                      | has `MomentumCallNotes__c`. `QuoteAccountId`.                                                                                     |
| Lumenix Scale (note's product)             | Product2 `01tWs00000Fxt33IAB`             | `Product2Id`.                                                                                                                     |
| **Lumenix selling-model-bound PBE ($500)** | `01uWs000006juYrIAI`                      | bound to Term Annual `0jPWs000000hI1iMAE`; must be in the synced `Price_Book_Entry_Decision_Table_v2`. Use as `PricebookEntryId`. |
| Lumenix bare PBE — **do NOT use**          | `01uWs000006juXFIAY`                      | no selling model → clone fails `ProductDetailsNotFound`.                                                                          |
| Standard Price Book                        | `01sWs000003beSzIAI`                      | `Pricebook2Id`                                                                                                                     |
| Billing Treatment (USA Advance)            | `1BTWs0000005AErOAM`                      | REQUIRED on the line or clone can't resolve product                                                                               |
| Lightning base URL                         | `https://arm-laulima26.my.salesforce.com` | record links: `<base>/lightning/r/Quote/<qid>/view`.                                                                              |
| Org (WRITE)                                | `laulima26`                               | org id `00DWs00000RvBGwMAN`                                                                                                        |

⚠ `Lumenix Scale` **has** `CanRamp = false`**, and that is CORRECT.** `Product2.CanRamp` gates
**legacy line ramps only** — a group ramp lives on `QuoteLineGroup` (`IsRamped` +
`groupRampAction`) and never reads it. If a build fails, do not chase this flag: it is
`createable=false / updateable=false` on v68.0, so nothing can set it anyway. Same for the
absent `ProductRampSegment` rows — also line-ramp-only. The real product-side failure mode is
using the **bare PBE** (`ProductDetailsNotFound`), not `CanRamp`.

### Build chain — the fixed MCP sequence each subagent runs (native)

Each subagent builds one quote via this chain. Start Oct 1 2026. Steps 1–5 are the FLAT build (qty
constant per segment — clone copies year 1 as-is). **FAITHFUL mode adds step 4b** (reprice each later
segment). **Every** `attributes` **block MUST carry** `"method"` (POST on place, PATCH on EditGroup/line) —
omitting it fails `INVALID_API_INPUT: Can't find the method attribute in the header`. Copy the JSON
graphs literally (subagents: these are in your own auto-loaded primer — do not improvise them).

1. `placeSalesTransaction` — Quote + QuoteLineGroup + segment-1 line.
  `pricingPref:"System"`, `taxPref:"Skip"`, `configurationPref:{configurationMethod:"Skip"}`:
   → returns `salesTransactionId` (the quote id).
2. `soqlQuery` — `SELECT Id FROM QuoteLineGroup WHERE QuoteId='<qid>'`
3. `placeSalesTransaction` **with** `groupRampAction:"EditGroup"` (`taxPref:"Skip"`) — PATCH quote+group into segment 1:
  ```json
   "graph":{"graphId":"g2","records":[
     {"referenceId":"<qid>","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<qid>"}}},
     {"referenceId":"<gid>","record":{"attributes":{"type":"QuoteLineGroup","method":"PATCH","id":"<gid>"},"StartDate":"2026-10-01","EndDate":"2027-09-30","SortOrder":1,"IsRamped":true,"SegmentType":"Yearly"}}
   ]}
  ```
4. `cloneSalesTransaction` ×(years−1) — add each later segment (copies the last as-is):
  `{inputs:[{recordIds:["<last ramped group id>"], salesTransactionId:"<qid>", lineScope:"AllLines"}]}`
   where `<last ramped group id>` = `SELECT Id FROM QuoteLineGroup WHERE QuoteId='<qid>' AND IsRamped=true ORDER BY SortOrder DESC LIMIT 1`.
   **FLAT mode stops here** and goes to step 5.

4b. **FAITHFUL mode only — reprice all later segments in ONE call (skip in flat mode).** Do this as
   exactly **two calls**, not per-segment — batching is the whole optimization (fewer calls = fewer
   inter-call stall windows, the real cost on the parallel path):

- **One** `soqlQuery` for every segment's line, ordered so row `i` = year `i`:
`SELECT Id, QuoteLineGroup.SortOrder FROM QuoteLineItem WHERE QuoteId='<qid>' ORDER BY QuoteLineGroup.SortOrder`
(one line per segment here — row 1 = Yr1 base, row 2 = Yr2, …).
- **One** `placeSalesTransaction` **PATCH graph** carrying the quote header + a line PATCH for **every
later segment** (years 2..N) at once (`taxPref:"Skip"`; year 1 base is never patched):

   Per-year ladder (cumulative-active qty; year 1 is the base built in step 1, never patched):

- **3-Year:** Yr1 qty 100 disc 0 · **Yr2 qty 200 disc 10** · **Yr3 qty 300 disc 15** (2 line records)
- **4-Year:** Yr1 qty 50 disc 0 · **Yr2 qty 100 disc 5** · **Yr3 qty 150 disc 10** · **Yr4 qty 200 disc 15** (3 line records)
- If the batched graph ever errors, fall back to one PATCH per line (same record shape, one line each).

5. `soqlQuery` **readback** — confirm the ramp:
  `SELECT Product2.ProductCode,RampIdentifier,Quantity,Discount,TotalPrice FROM QuoteLineItem WHERE QuoteId='<qid>'`
   Clean = N segments, N lines, **every line with a** `RampIdentifier`. FAITHFUL: qty + discount step
   up per the ladder above; FLAT: qty constant, discount null.

### Parallel build — two subagents, orchestrator narrates (native)

The two quotes are independent records, so build them **concurrently: one background subagent per
quote** (never per segment — within a quote the chain is sequential, each clone needs the prior group
id). The orchestrator (this session) owns the whole conversation; subagents do the plumbing
silently. Three levers make it fast — apply all three:

**Lever 1 — dispatch and prose in SEPARATE turns.** Tool calls fire only after a turn finishes
generating, so narrating in the same turn as the dispatch blocks the build. Dispatch in one turn, write
the opening line in the next, so the prose generates *while the subagents build*.

**Lever 2 — dispatch prompts are PARAMETERS-only, never the recipe JSON.** Subagents auto-load this
same primer, so they already have the literal graphs. Pasting the JSON into the dispatch is ~30s of
generation (the old dead air); a short parameters prompt is ~5s and keeps the `"method"` safety (the
subagent copies literal JSON from its own primer).

**Lever 3 —** `subagent_type: general-purpose` **+** `model: haiku`**.** ⚠ Agent-type tool access ≠ model.
`general-purpose` has the `revenue-cloud` MCP server; `model: haiku` overrides speed independently.
Do **NOT** use a haiku *tool-agent type* (e.g. `tools-haiku`) — its allowlist excludes the MCP server,
so it can't call the ramp tools and returns a *plan* instead of a built quote. Subagents do zero
reasoning, so haiku's faster turns kill the inter-call latency.

**Sequence:**

1. **Turn A — read the note, then dispatch both builders. No visible text.**
  - `soqlQuery`: `SELECT Name, MomentumCallNotes__c FROM Account WHERE Name = 'Acme'`
  - **Decide the mode first** from the user's prompt (see *Two modes* up top): FLAT unless a faithful
  trigger word is present. Pass the mode into BOTH dispatches.
  - Dispatch two subagents, `run_in_background: true`, both in one message (`general-purpose` +
  `model: haiku`). Each dispatch is a short parameters-only prompt naming the mode, e.g.:
    > *"Build the 3-Year ramp quote in **FLAT** mode by following the native build chain in your
    > auto-loaded CLAUDE.md exactly (place → group-id read → EditGroup → clone×(N−1) → readback),
    > copying the literal JSON graphs there. Parameters: qty 100, 3 segments, name*
    > `Acme Momentum - 3-Year Ramp`*. Return structured data only (quote id, per-segment
    > name/qty/discount/TotalPrice, each line's* `RampIdentifier`*, header status) — no narration."*
    >
    > For **FAITHFUL** mode, change one clause: *"…in **FAITHFUL** mode (run step 4b — reprice each
    > later segment to the per-year ladder in your primer: 3-Year qty 100/200/300 disc 0/10/15)…"* —
    > and give the 4-Year builder its own ladder (qty 50/100/150/200 disc 0/5/10/15).
  - Per-quote parameters: **3-Year** qty **100**, 3 segments (place + EditGroup + clone×2). **4-Year**
  qty **50**, 4 segments (place + EditGroup + clone×3). Both: Lumenix `01tWs00000Fxt33IAB`, PBE
  `01uWs000006juYrIAI`, unit 500. Faithful adds step 4b: one SOQL + one batched reprice PATCH.
  - ⚠ Accepted tradeoff: the "Ran 2 agents…" indicator appears before the deal line (Turn A has no
  prose). That's deliberate — leading with prose would delay the dispatch.
2. **Turn B — FRONT-LOAD the deal narration here, while the subagents build.** No tool calls; pure
  prose that overlaps the build (see *Why front-loading is free* below). This is the one place to
   spend words freely — the user reads substance instead of watching a spinner. Budget ~4–8 sentences:
   the expansion story (what Meredith & Bob asked for), **both** options framed side by side (3-year =
   faster commit, 4-year = same adds spread longer), and the trade-off you'll quantify once the quotes
   land. Do NOT wait for a result to start this; do NOT narrate mechanics or status. End the turn here
   so the prose is *done generating* before the first quote returns.
3. **Present each quote as its subagent returns** — don't block on both. Keep each beat **SHORT** (the
  table + link + one trade-off line): a long paragraph here delays showing a *finished* quote 1:1,
   because you only process the returned result at a turn boundary. Show that quote's table
   (§Presentation) with its live link, then the second when it lands.
4. **Closing summary — SHORT.** The two-model trade-off, both TCVs, both links. One or two sentences.

**Why front-loading is free (the timing model):** subagents run in the background on the transport —
their execution overlaps the orchestrator's text generation, so Turn B prose costs the build *nothing*.
The asymmetry: the orchestrator only ingests a returned result at a **turn boundary**, so prose you're
still generating *when a quote lands* delays presenting it 1:1. Hence the shape — spend words in Turn B
(nothing to wait on yet), stay terse in steps 3–4 (a result is landing). The mid-build **stalls**
(the tens-of-seconds inter-call gaps) happen *inside a subagent's own turn* — the orchestrator is
dormant then and cannot narrate into them; front-loaded Turn B prose is the only lever, and it only
covers the *early* part of the wait. Never fill with mechanical status to bridge a stall (banned — see
*How to talk*); if Turn B prose runs out before the first quote, stop and wait silently.

**If a subagent returns a plan (no MCP tools)** → wrong agent type; use `general-purpose`. **If a
subagent errors** (dropped `"method"`, `ProductDetailsNotFound`) → the orchestrator rebuilds that one
quote **sequentially in-session** via the build chain above, so the error is visible and fixable.

### Presentation — in-chat table, always linked (native)

Per quote: a per-segment table + native TCV (sum of segment `TotalPrice`), then one plain sentence on
how native models the deal. Columns depend on mode:

- **FLAT:** segment · year span · users · unit · segment total. All segments same users, no discount.
- **FAITHFUL:** segment · year span · users (growing) · discount · segment total. Users step up per the
ladder (3-Yr 100/200/300, 4-Yr 50/100/150/200) and discount rises (0/10/15 · 0/5/10/15).

**Every table carries a clickable quote link on its heading:**

> **`[Acme Momentum — 3-Year Ramp](<base>/lightning/r/Quote/<qid>/view)`** (Lumenix Scale, starting Oct 1 2026)

Build the URL from the Lightning base URL above. Repeat both links in the closing summary. Use the
segment `TotalPrice` values the subagent returns for the totals — do not hand-compute (discount makes
the arithmetic non-obvious).

### How to talk — native (a business conversation, not a tooling session)

You're the rep's assistant walking them through a deal. The parallel run leaks build chatter easily,
so this is strict:

- **First words are the deal**, never tools/servers/instructions. Lead with what Acme asked for — the
two ramp options, the expansion story, the trade-off.
- **Never narrate plumbing or mechanics** — no "querying/verifying/subagent/in parallel", tool names,
internal ids, or the words *demo*/*test*/*scenario*.
- **Never announce build status as mechanical state.** ⚠ Banned: *"The 3-Year Ramp is built."* ·
*"Still waiting on the 4-Year quote."* · *"Both quotes are built."* · *"Ran 2 agents."* Present each
quote as a business option instead:
  - ✅ FLAT: "Here's the 3-year option — 100 users a year across three ramped terms. Let me lay the
  4-year alternative next to it."
  - ✅ FAITHFUL: "Here's the 3-year option — the base grows from 100 to 300 users as the ramp steps up,
  with the 10% and 15% discounts baked into years two and three. Here's the 4-year next to it."
  - ✅ closing (use THIS run's returned totals): "The 3-year commits to faster expansion; the 4-year
  spreads the same adds over a longer horizon. Both are in Draft for your review — [3-Year](…) · [4-Year](…)."
- **Three narration beats, nothing between:** opening deal line → each quote's table+link as it lands →
closing trade-off with both TCVs and links.
- **One honest caveat, as business fact — pick the one for your mode, say it once:**
  - FLAT: native builds level co-sized segments, so yearly spend is flat and TCV differs from a
  discounted co-term quote.
  - FAITHFUL: native models a growing active base (each year the full headcount is repriced), whereas
  a cohort quote prices only each year's *new* users — so the native TCV runs higher and won't match
  a cohort total.

---

## Cohort model — flat co-terming lines

Cohort-line ramp-quote demo: each year's cohort is its own flat `QuoteLineItem`, no
`QuoteLineGroup`, no `RampIdentifier` — built with the standard `industries/revenue-cloud`
server's `createSalesTransaction`, NOT the native `placeSalesTransaction`/`cloneSalesTransaction`
tools.

**The whole 2-quote demo is exactly 4 MCP calls — no more:**
1. `soqlQuery` — read the Acme Momentum note (Step 1).
2. `createSalesTransaction` — 3-year quote, all cohorts inline in `products`.
3. `createSalesTransaction` — 4-year quote, all cohorts inline.
4. `soqlQuery` — ONE combined verify over both quote ids.

**Never** run an existence/reuse check, per-year `addLines`, `repriceSalesTransaction`, or a second
verify — each is a wasted round-trip. Build fresh; there's nothing to reuse.

### Step 1 — read the note (the note IS the ask)

Standard server's **`soqlQuery`** tool (arg is **`q`**, not `query`), resolve Acme by name:
```
q = "SELECT Name, MomentumCallNotes__c FROM Account WHERE Name = 'Acme'"
```
The note describes what the customer asked for — quote count, ramp length(s), users added per year,
the discount offered each year. **Interpret it into concrete quotes; you're translating a sales
conversation, not transcribing a spec.** Then go straight to building.

Expected shape (the live read is authoritative) — Meredith & Bob, 2 quotes, both Lumenix Scale,
start **Oct 1 2026**, co-terminating at deal end:
- **3-Year Ramp:** +100 users/yr; Yr2 10%, Yr3 15% (on that year's adds). Co-term 2029-09-30.
- **4-Year Ramp:** +50 users/yr; Yr2 5%, Yr3 10%, Yr4 15%. Co-term 2030-09-30.

Do NOT narrate the read as confirming/matching anything — see *How to talk* below.

### Fast path — pre-resolved ids (cohort)

**Verified on `laulima26` 2026-08-06** — both quotes built live and read back at the expected
economics: 3-yr `0Q0Ws000009RgpBKAS` (3 lines, 50000/45000/42500, TCV **$282,500**), 4-yr
`0Q0Ws000009RgqnKAC` (4 lines, 25000/23750/22500/21250, TCV **$237,500**).

⚠ **The discount field is `discountPercent`, not `discount`.** This corrects the upstream kit's
own primer, which has it backwards for this org's current API version — verified live from this
cloud session on 2026-09-11: `discount` gets rejected outright
(`JSON_PARSER_ERROR: Unrecognized field "discount"`) by both `createSalesTransaction` and
`addLines` on `industries/revenue-cloud` here, while the tool's actual input schema (confirmed via
the primed tool-list cache) defines `discountPercent` (0-100, e.g. 10 = 10% off) and
`discountAmountPerUnit` as the two valid discount fields — mutually exclusive, use
`discountPercent`. A rejected line is *skipped, not fatal*: the quote builds with fewer lines and
the totals silently come out low. **Always check the line count** (3 lines for the 3-yr quote, 4
for the 4-yr) before presenting — if it's short, a line got silently dropped.

| Thing | laulima26 id | Notes |
|---|---|---|
| Acme account | `001Ws00005vw5s0IAA` | has `MomentumCallNotes__c`. Use as `accountId`. |
| Lumenix Scale (`SUB-LMX-002`) | Product2 `01tWs00000Fxt33IAB` | $500/user/yr. Use as `productId`. |
| PricebookEntry ($500) | `01uWs000006juYrIAI` | Standard Price Book `01sWs000003beSzIAI` |
| Selling model | `0jPWs000000hI1iMAE` | Term Annual, TermDefined 1/Annual (via ProductSellingModelOption) |
| MCP server | standard `industries/revenue-cloud` | inline `products`; NO custom standup, NO groupRampAction |
| Org alias | `laulima26` — WRITE here | |

### Build recipe — ONE `createSalesTransaction` per quote (cohort)

All cohort lines go inline in `products`, so a whole quote = 1 call (do NOT use separate `addLines`):
```
{type:"Quote",                        // REQUIRED — omit → "type must be 'Quote' or 'Order'"
 accountId:"001Ws00005vw5s0IAA",
 name:"Acme Momentum - Lumenix Scale - 3-Year Ramp",
 products:[                           // one cohort per year, ALL inline
   {productId:"01tWs00000Fxt33IAB", quantity:100, unitPrice:500,   // unitPrice REQUIRED (else $50 default)
    startDate:"2026-10-01", endDate:"2029-09-30",                  // co-term end shared by ALL cohorts
    subscriptionTerm:12, pricingTermUnit:"Months"},                // year-1 base: NO discount
   {…, startDate:"2027-10-01", endDate:"2029-09-30", discountPercent:10},
   {…, startDate:"2028-10-01", endDate:"2029-09-30", discountPercent:15}
 ]}
```
Returns `salesTransactionId` + `lineIds`, already priced (`CompletedWithPricing`). The 4-year quote
is the same shape: 4 cohorts, qty 50, co-term 2030-09-30, disc 0/5/10/15 (as `discountPercent`).

**Cohort-line model:** each year's cohort is a separate QuoteLineItem with its own StartDate and a
**shared co-term EndDate**; that year's discount applies only to its **incremental** cohort (the base
is never discounted). NO QuoteLineGroup, NO RampIdentifier (that's the native-groups path — see above).

**Null-field caveat:** created lines come back with `StartDate`, `SubscriptionTerm`, and
`ProductSellingModelId` all **null** regardless of what was passed; `EndDate` and
Quantity/UnitPrice/Discount/TotalPrice persist correctly (pricing unaffected). So derive years-remaining
from **cohort order, not StartDate**, and never surface this in output (internal note only).

### Verify + compute TCV (cohort)

ONE combined `soqlQuery` over both quotes (don't loop per-quote):
```
SELECT QuoteId, Quantity, Discount, TotalPrice FROM QuoteLineItem
WHERE QuoteId IN ('<3yr qid>','<4yr qid>') ORDER BY QuoteId, Discount
```
Say **nothing** about running it, and emit NO message between building the quotes and the table.
Do not narrate the fetch in ANY words — banned: "confirming pricing", "verifying", "pulling the line
totals", "pulling the numbers", "now getting the totals to build the comparison", "one combined
check". The user doesn't know a query runs. After the quotes are built, your next message IS the
table (§presentation) — go straight there, silently.

**Multi-year TCV — compute client-side.** The API stores each cohort's **annual** net value (line
`TotalPrice`) and does NOT scale by term. A cohort persists to co-term, spanning `(years − i)` years
(i = 0-based cohort order). **TCV = Σ annual_TotalPrice × (years − i).**

**Self-check before presenting** (these are the correct results — investigate if yours differ, but
never tell the user your numbers "match expected"):
- **3-year** (+100/yr, disc 0/10/15): TotalPrice 50000/45000/42500 → header $137,500, TCV **$282,500**
  (50000×3 + 45000×2 + 42500×1).
- **4-year** (+50/yr, disc 0/5/10/15): 25000/23750/22500/21250 → header $92,500, TCV **$237,500**.

### Discount policy (hard guardrail — cohort)

- **Never create a quote with >15% discount** on any line, any product.
- On a >15% request, do NOT create the quote until reduced to ≤15% or approval is confirmed. Instead:
  1. State the requested % exceeds the 15% max.
  2. Lead with a recommendation + insights.
  3. Offer next actions as structured options (AskUserQuestion): **Cap at 15%** · **Increase volume**
     (grow the deal, stay ≤15%) · **Deal desk approval** (route exception; create at 15% meanwhile).

### Presentation — in-chat table FIRST, then dashboard in the pane (cohort)

Both required, **in this order**. The table is a finished reply on its own; only after it's on screen
do you touch the dashboard. (Building the dashboard means emitting several KB into the Write tool —
silent output. Starting it before the table = a blank screen, the #1 UX bug here. Never announce
"generating the dashboard" until the table is displayed.)

**1. In-chat — a proper Markdown TABLE (not bullet lists).** ONE side-by-side comparison, identical
columns per quote, filled with this run's numbers:

| Cohort | 3-Year — Users | 3-Year — Disc | 3-Year — Annual | 4-Year — Users | 4-Year — Disc | 4-Year — Annual |
|---|---|---|---|---|---|---|
| Year 1 (base) | 100 | — | $50,000 | 50 | — | $25,000 |
| Year 2 add | 100 | 10% | $45,000 | 50 | 5% | $23,750 |
| Year 3 add | 100 | 15% | $42,500 | 50 | 10% | $22,500 |
| Year 4 add | — | — | — | 50 | 15% | $21,250 |
| **Year-N spend** | | | **$137,500** | | | **$92,500** |
| **Multi-year TCV** | | | **$282,500** | | | **$237,500** |

Then one or two plain sentences on the trade-off (faster expansion vs lower annual commitment).

**2. Dashboard — generate to stdout, then Write it EXACTLY ONCE.** The pane renders an `.html` ONLY
when the file is created by the **Write tool** — a file produced by Bash (`> file.html`, redirection,
`--out`, a script writing a file) does NOT trigger the pane. The CSS must be inline (the pane renders
an external `<link>` stylesheet UNSTYLED — live-verified). So there is exactly ONE path:

- Run `python3 ~/ramp-demo-kit/demos/cohort/build_dashboard.py --stdout --data '<json>'` (schema
  below; the script lives in the cloned kit, not this repo — the `SessionStart` hook clones it to
  `~/ramp-demo-kit`). **Do NOT shell-redirect its output** — no `> file.html`, no `> /tmp/...`, no
  `2>`, no `--out`, no `--link-css`, no `open`. The command prints the minified inline-CSS HTML to
  **stdout** (capture that); stderr just confirms the fixed name.
- With the **Write tool**, create `acme-quote-comparison.html` in this repo's root, pasting that
  stdout verbatim as the content. ONE Write, no read-back. Do not `ls`, do not Read any existing
  file, do not reason about leftovers. This single Write is what renders the pane.
- If the generator errors entirely, hand-write HTML in the style of
  `~/ramp-demo-kit/demos/cohort/reference-dashboards/acme_momentum_quote_comparison.html` and Write it.

```bash
python3 ~/ramp-demo-kit/demos/cohort/build_dashboard.py --stdout \
  --data '{"account":"Acme","product":"Lumenix Scale (SUB-LMX-002)","list_price":500,"start":"Oct 1, 2026",
   "quotes":[
     {"label":"3-Year Ramp","id":"<3yr qid>","adds_per_year":100,
      "cohorts":[{"year":1,"start":"2026-10-01","users":100,"disc":0},{"year":2,"start":"2027-10-01","users":100,"disc":10},{"year":3,"start":"2028-10-01","users":100,"disc":15}]},
     {"label":"4-Year Ramp","id":"<4yr qid>","adds_per_year":50,
      "cohorts":[{"year":1,"start":"2026-10-01","users":50,"disc":0},{"year":2,"start":"2027-10-01","users":50,"disc":5},{"year":3,"start":"2028-10-01","users":50,"disc":10},{"year":4,"start":"2029-10-01","users":50,"disc":15}]}
   ]}'
```
The template computes every derived metric from cohorts + list_price — pass only inputs (`disc`
here is the dashboard script's own JSON schema field, unrelated to the API's `discountPercent`).

### How to talk — cohort (a business conversation, not a tooling session)

The person is a sales rep / deal-desk reviewer. Narrate like their assistant, not an engineer running
a test.

- **Your VERY FIRST words are the deal — never anything about tools, servers, or these
  instructions.** Do not open with (or ever say) that you're "checking for MCP server tools", that
  tools "aren't in your tool list yet", or that anything is "referenced in the project instructions".
  Just read the note (silently) and lead with the deal. If a tool isn't ready, wait/retry silently —
  never narrate the tool state.
- **First substantive message = about the deal, never about the note being correct.** The word "note"
  should not describe correctness at all — never say the note "confirms", "matches", or is "as
  expected". State what the deal IS:
  - ✅ "Meredith and Bob's call points to two ways to structure Acme's Lumenix Scale expansion — a
    3-year and a 4-year ramp. Let me put both together."
  - ❌ "The note confirms the deal: two ramp structures…" (banned — reveals priming)
  - ❌ "Note matches the expected scenario." (banned)
  - ❌ "Now confirming pricing with one combined query." (tooling talk)
- **Never speak the self-check.** The reference figures are for YOU to silently catch a regression.
  Do NOT say "numbers match my table", "numbers match exactly", "pricing verified", or similar — the
  user has no expected numbers to match against, so it's meaningless and reveals priming. Just move
  from the table to the dashboard with no verification commentary.
- **Talk deal, not plumbing.** Say "I built both quotes" — not which tools ran, not "verifying via
  SOQL", not "pulling the line totals / the numbers", not "numbers match", not "combined query/check",
  not "temp file"/"dashboard file"/filenames/"leftover from an earlier run", not internal ids, and
  never the words *demo*/*test*/*scenario*/*self-check* unless asked. Ideally emit only THREE
  messages total: (1) the opening deal line, (2) the table + trade-off, (3) the closing summary once
  the dashboard is up. No status chatter between them.
- **Guardrail gracefully** per the discount policy, in plain language.
- Nothing is shown in the org UI — the call note is just the starting context.

### Revenue Cloud reference (cohort)

- Use **`QuoteAccountId`** (not `AccountId`) to get the Account on a Revenue Cloud Quote.

---

## Clean up after a run

Quotes created here (either model) are real Draft records in `laulima26`. Delete via the MCP
connector's `soqlQuery`/data tools, or ask this session to do it — there's no local `sf` CLI in
this container's cleanup path.

## MCP setup (automatic in this cloud session)

The `.claude/hooks/session-start.sh` `SessionStart` hook clones `bgaldino/ramp-demo-kit` into
`~/ramp-demo-kit`, patches its `tools/ramp_auth.py` with a headless `client_credentials` grant
(the upstream kit only supports interactive browser OAuth, which doesn't work in a cloud
session with no reachable localhost callback), mints a token, and writes `.mcp.json` at this
repo's root pointing at the kit's `tools/mcp_multiplex_proxy.py` — the same multiplexer that
fronts both the cohort (`industries/revenue-cloud`) and native (`custom/rampdealsconnect`)
servers behind one connector.

This requires the **`RAMP_SF_CSEC`** environment variable (the ECA's consumer secret) to be
configured in this environment's settings — it is intentionally never committed to this repo.
Without it, the hook still writes `.mcp.json` but the connector will fail to authenticate.
