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
  The menu bar removes spacing between time units; for weekly windows it rounds
  UP to the next hour with an explicit approximation mark. Full minutes remain
  in the panel and accessibility/tooltip. Keep the two provider modules compact.
- Claude defaults to **History**: orange observations only, on their actual time
  span (minimum one hour), with the unchanged 0–100% vertical scale. Flat recent
  readings must remain flat; do not amplify tiny changes or invent older data.
- **Projection** is a separate selectable view. Red estimates are dashed; gray
  budget starts at the same estimated current balance and goes to zero at reset,
  never at an invented historical 100%. Label low-confidence projections.
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
- **Single weekly chart**, per João's final correction: no Overview, History or
  Projection tabs. Show real observations plus dashed forecast and allowed pace
  until reset together, with a visible forecast boundary and confidence. Without
  a valid forecast, show only recorded history. Never call an estimate observed.
  João approved the rest of the panel; preserve its layout, colors and controls.
- Keep 0–100 vertically, actual time horizontally, no synthetic 100% history.
  Shared line widths, axes, padding and typography; yellow Codex, orange Claude.
- Counts/resets are never summed. Five-hour data crosses the bridge explicitly;
  weekly prediction never uses five-hour or Spark consumption.
- Shared body scrolls above a fixed footer. Current pace, remaining-at-reset,
  allowed pace and confidence remain readable. Status/low confidence are textual.
- Native 390×590 QA covers single/two/three limits, no Spark, expired cached Spark,
  sparse/flat history, estimate, stale/error and missing data, plus both menu themes.
  No collector cadence, authentication, schema or billing inference changes.
