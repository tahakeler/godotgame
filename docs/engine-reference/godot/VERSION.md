# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.2 |
| **Project Pinned** | 2026-09-19 |
| **Last Docs Verified** | 2026-02-12 (4.6 content — 4.7 notes not yet gathered) |
| **LLM Knowledge Cutoff** | May 2025 |
| **Risk Level** | HIGH |

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4 through
4.7 introduced significant changes that the model does NOT know about.
Always cross-reference this directory before suggesting Godot API calls.

**The project runs 4.7.2, but the reference docs below were written for 4.6.**
Anything specific to 4.7 is unverified. Run `/setup-engine refresh` to close
that gap before relying on these docs for 4.7-specific APIs.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |
| 4.7 | 2026 | HIGH | Current project version — changes not yet documented here |

## Migration Notes — 4.6 → 4.7

Applied on 2026-09-19 when the project was opened in Godot 4.7:

- `config/features` updated to `PackedStringArray("4.7", "Forward Plus")`
- `renderer/rendering_method="forward_plus"` removed — it is the 4.7 default
- C# support dropped from the project (the installed editor is the standard
  build, not the .NET build), so the `[dotnet]` section was removed

## Verified Sources

- Official docs: https://docs.godotengine.org/en/stable/
- 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
- 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
- Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
- Release notes: https://godotengine.org/releases/4.6/
