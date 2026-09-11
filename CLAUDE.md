# CLAUDE.md — Ramp-quote workspace (laulima26, cloud session)

Revenue Cloud ramp-quote demos on **laulima26**, running conversationally from a Claude Code
on the web session. This repo root stands in for the `demos/cohort/` folder in
[bgaldino/ramp-demo-kit](https://github.com/bgaldino/ramp-demo-kit) — a `SessionStart` hook
(`.claude/hooks/session-start.sh`) clones that kit into the container, mints an MCP access
token, and writes `.mcp.json` at this repo's root automatically at session start. The
`revenue-cloud` connector fronts only the standard `industries/revenue-cloud` server (cohort
lines, `soqlQuery`, `createSalesTransaction`) — everything below is reachable from this one
session.

**MCP connector prerequisite:** this only works if the `RAMP_SF_CSEC` environment variable
(the ECA's consumer secret) is configured in this environment's settings on claude.ai/code.
Run `/mcp` — it should show `revenue-cloud` Connected. If it isn't, the hook's stderr output
(visible in session startup logs) will say why — almost always a missing/wrong `RAMP_SF_CSEC`.

The standard prompt this workspace answers:

> **Read the Momentum Call note for Acme account and build the ramp quotes for review.**

That always means the cohort build below (`createSalesTransaction` with inline per-year cohort
lines) — there is no other model wired into this session.

---

## Cohort model — flat co-terming lines

Cohort-line ramp-quote demo: each year's cohort is its own flat `QuoteLineItem`, no
`QuoteLineGroup`, no `RampIdentifier` — built with the standard `industries/revenue-cloud`
server's `createSalesTransaction`.

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
is never discounted). NO QuoteLineGroup, NO RampIdentifier.

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

Quotes created here are real Draft records in `laulima26`. Delete via the MCP connector's
`soqlQuery`/data tools, or ask this session to do it — there's no local `sf` CLI in this
container's cleanup path.

## MCP setup (automatic in this cloud session)

The `.claude/hooks/session-start.sh` `SessionStart` hook clones `bgaldino/ramp-demo-kit` into
`~/ramp-demo-kit`, patches its `tools/ramp_auth.py` with a headless `client_credentials` grant
(the upstream kit only supports interactive browser OAuth, which doesn't work in a cloud
session with no reachable localhost callback), mints a token, and writes `.mcp.json` at this
repo's root pointing at the kit's `tools/mcp_multiplex_proxy.py`, pinned via `SF_MCP_SERVERS`
to the single standard `industries/revenue-cloud` server — no other upstream is ever opened,
so there's nothing multiplexed.

This requires the **`RAMP_SF_CSEC`** environment variable (the ECA's consumer secret) to be
configured in this environment's settings — it is intentionally never committed to this repo.
Without it, the hook still writes `.mcp.json` but the connector will fail to authenticate.
