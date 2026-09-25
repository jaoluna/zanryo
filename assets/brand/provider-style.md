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
- No gradients, new charts, new layouts, aggregation or forecast for Claude.
- Keep accessibility labels and visible remaining percentages (100 to 0).

## Asset provenance

`claude-radial.svg` preserves the radial path from the official wordmark at
https://claude.com/ (retrieved 2026-09-25). Only the enclosing square viewport
and monochrome fill differ. The original site uses `#D97757` for this path.
The 128px PNG is a transparent rasterization with 4px inset, loaded as a native
template image for both menu-bar and popover rendering. This is a provider
identifier, not Zanryo branding or an endorsement. Rights remain with Anthropic.
