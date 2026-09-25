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
