# Provider identity

Approved visual amendment, 2026-09-25: replace the Anthropic lettermark with
Claude's radial symbol. Keep the current layout, typography, dragon identity,
quota semantics, controls and collection unchanged. This is a color/mark change.

- Claude: official radial mark, transparent monochrome mask; terracotta `#D97757`
  in the provider selector, quota values and menu-bar module.
  A darker `#A04428` variant keeps Claude legible in the light system menu bar.
- OpenAI/Codex: existing knot glyph and Zanryo yellow `#F2B632` remain unchanged.
- Common popover: background `#0C0E10`, surface `#16191D`, text `#F8F3E8`,
  secondary text `#B0B6C1`; warnings remain distinct from the brand accent.
- No gradients or aggregation between providers/windows.
- Keep accessibility labels and visible remaining percentages (100 to 0).

## Asset provenance

`claude-radial.svg` preserves the radial path from the official wordmark at
https://claude.com/ (retrieved 2026-09-25). Only the enclosing square viewport
and monochrome fill differ. The original site uses `#D97757` for this path.
The 128px PNG is a transparent rasterization with 4px inset, loaded as a native
template image for both menu-bar and popover rendering. This is a provider
identifier, not Zanryo branding or an endorsement. Rights remain with Anthropic.

## Dashboard completion, same-day user correction

João explicitly requested the missing graph and metrics. Reuse the existing
dashboard grammar: independent five-hour/weekly quota strip, weekly timeline,
pace/forecast rows and compact source/refresh footer. Existing forecast engine,
real Claude weekly samples only, orange observed/red estimated/gray budget.
Never invent an observed 100% cycle-start anchor. Early history shows observations
before forecast is available. Stale/error hides projections, not observations.
No billing/plan inference. Keep 390x590; long content scrolls above controls.

## Readable time and Claude history, 2026-09-25 (chart navigation superseded below)

- Reset countdowns share one elapsed-time formatter. Include minutes instead of
  dropping up to 59 minutes; round up only the final partial minute. Absolute
  resets use the system's local time, never a manually added hour.
  The menu bar uses days + HH:MM (5d23:55) for multi-day windows, without an
  approximation prefix or whole-hour rounding. Short windows retain h/m units.
  Full units remain in the panel and accessibility/tooltip.
- Claude defaults to **History**: orange observations only, on their actual time
  span (minimum one hour), with the unchanged 0–100% vertical scale. Flat recent
  readings must remain flat; do not amplify tiny changes or invent older data.
- The historical separate Projection tab and current-balance gray budget were
  superseded by João's single-chart and fixed ideal-cycle corrections below.
- Preserve both quota windows, all metrics and the fixed refresh footer. Disable
  projection for missing/stale data. Validate a real-shaped short, flat 97%
  history as well as declining, collecting and stale fixtures.

## Unified dashboard polish, 2026-09-25

João requested Claude's graph at the Codex standard and an updated Codex/Spark
panel. This extends the selected dashboard direction, not a new brand concept.
- Both providers use the same quota strip, 100→0 meter and single chart.
  A single supplied window gets a full-width horizontal summary; two use equal
  columns. An optional Spark window is a compact extra row, never an empty column.
  Missing or expired optional limits are hidden; historical samples remain stored.
- **Single weekly chart**: no Overview, History or Projection tabs. João rejected
  the redesigned graph and requested the original `6801b21` composition again.
  Restore the `WEEKLY FORECAST` / two-line `CURRENT PACE` header, daily ticks,
  continuous red depletion forecast, original plot geometry and compact legend.
  Remove the vertical forecast boundary and added history/confidence caption.
  Show real observations and the independent dashed gray budget/ideal guide.
  The guide
  runs from 100% at reset minus seven days to 0% at reset, independently of the
  current balance or forecast availability. It is not observed usage. Stale data
  keeps the saved cycle guide/history but never a current projection.
  João approved the rest of the panel; preserve its layout, colors and controls.
- Keep 0–100 vertically, actual time horizontally, no synthetic 100% history.
  Shared line widths, axes, padding and typography; yellow Codex, orange Claude.
- Counts/resets are never summed. Five-hour data crosses the bridge explicitly;
  weekly prediction never uses five-hour or Spark consumption.
- Shared body scrolls above a fixed footer. Current pace, remaining-at-reset,
  available-per-day budget and confidence remain readable. The current budget
  is distinct from the gray ideal-cycle reference. Low confidence is textual.
- Native 390×590 QA covers single/two/three limits, no Spark, expired cached Spark,
  sparse/flat history, estimate, stale/error and missing data, plus both menu themes.
  No collector cadence, authentication, schema or billing inference changes.

## Personal-plan design study and next data layer, 2026-09-25

Deferred by the graph-restoration request. These proposals are not an approved
next implementation step; restore the original graph before revisiting improvements.

The test-only `PlanDesignPreview` renders eight named personal-plan states:
Codex Free, Go, Plus, Pro 5x/20x; Claude Pro, Max 5x/20x. All balances and
windows are explicitly simulated. These fixtures do not ship in the app,
persist samples, infer billing tiers or change live account settings.

- One chart per provider, unchanged provider accents. The candidate panel is
  390x640 to accommodate a model-specific row and one optional value row;
  the installed panel remains 390x590. No additional navigation tabs.
- The live payload, not the plan name, must decide which windows appear.
  OpenAI `pro` alone does not distinguish 5x from 20x. Unknown stays unknown.
  Plus/Free/Go demo windows are illustrative, not a promise about every account.
- Fable on Max is a sublimit sharing the weekly allowance, not an extra bucket.
  Display remaining percentage of the Fable cap separately, explain the shared
  allowance, and never sum it with weekly remaining. Pro uses paid usage credits.
  No Fable percentage is installed until a supported live field is captured and
  its denominator/reset semantics are proven. The existing collector only
  supplies five-hour and aggregate-weekly limits.
- Spark remains conditional on a fresh explicit source field, not a plan badge.
- API-equivalent value gets one compact optional row with details on demand.
  Missing measurement is not $0. It is a retail API comparison for captured
  usage, not a bill, provider cost, actual subsidy or complete account value.

### Collection proposal (researched, not enabled)

Claude Code 2.1.282 is installed. The official statusline JSON (2.1.251+) can
supply `rate_limits.five_hour`/`seven_day` after an API response, together with
`cost.total_cost_usd`. Observe existing CLI events without launching another
Claude or requesting model work. An opt-in adapter must compose with, not
replace, the user's current statusline and preserve its stdout/exit behavior.
An atomic allowlisted payload can then be consumed through the Rust bridge.

Keep the current serialized `/usage` probe as manual/fallback collection:
statusline events originate in Claude Code, not Desktop. A timer replay of
cached JSON is not a new server observation. Reject future/out-of-order events,
expired windows, invalid percentages and gateway-only spend fields; do not
turn absent windows into zeros. Fresh event data can suppress the heavier
probe; no recent event means the current conservative fallback still runs.

Before activation: measure CPU/RSS/startups against the current five-minute
baseline; test absent/null fields, 100-used normalization, reset rollover,
duplicate/replayed events, concurrent sessions, existing statusline composition
and Desktop-only usage. Provider-only history currently cannot isolate accounts;
resolve identity/epoch separation before adding multi-account ingestion.

### API-equivalent measurement (not implemented)

Use actual per-request model/token records, not a conversion from quota percent.
Version rate cards and split uncached input, cache reads, cache writes and output;
respect long-context and speed tiers, and avoid double-counting cached input or
reasoning output. Unknown models/tiers stay unpriced with coverage shown.
For Claude, the official session cost is already a client-side estimate: do not
sum cumulative snapshots. Repeated delivery, resume, clear and session forks
need explicit deduplication. Local session coverage excludes other devices and
uncaptured app chats. Compare to the user's actual paid subscription over a
matching billing period, only after reliable coverage exists. No retroactive
full-rollout rescans on every refresh; incremental offsets and bounded I/O.

Official sources checked 2026-09-25:
- https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- https://learn.chatgpt.com/docs/pricing
- https://developers.openai.com/api/docs/pricing
- https://support.claude.com/en/articles/11049741-what-is-the-max-plan
- https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan
- https://code.claude.com/docs/en/statusline
- https://code.claude.com/docs/en/costs
