# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`zero_cached_image` is a published pub.dev package — a minimal, high-performance cached network image widget for Flutter. Two dependencies (`path_provider`, `crypto`), zero-copy disk reads via `ImmutableBuffer.fromFilePath()`, in-memory hash-keyed index flushed to disk debounced + atomic with backup recovery.

The sibling package `zero_cached_video` (`D:\Github\zero_cached_video`) reuses this cache machinery via the additive `cacheDirName` + `extensionAllowlist` constructor params introduced in 1.1.0 — when changing internals, check the sibling for the corresponding update.

## Important Sources

- **`zero_cached_image`** (this repo): `D:\Github\zero_cached_image` — published as `zero_cached_image` on pub.dev
- **`zero_cached_video`**: `D:\Github\zero_cached_video` — sibling, depends on this package's `ZeroCacheManager`
- **`publicos_client`**: `D:\Github\publicos_client` — primary consumer; uses `ZeroCachedImage` / `ZeroCachedImageProvider` for every persistent image and bans `Image.network` / `NetworkImage` (see vault feedback `feedback_zero_cached_image_everywhere.md`)

## Vault references

The vault is at `D:\Obsidian\jmsl\`. Always start a session by reading:

- `D:\Obsidian\jmsl\threads.md` — what's currently being worked on, where to register this session
- `D:\Obsidian\jmsl\wiki\zero_cached_image\` — canonical reference for this package (architecture, cache machinery, public API, gotchas). If something on this page disagrees with the code, the **code wins** — fix the wiki first, then proceed.
- `D:\Obsidian\jmsl\wiki\workflow.md` — full workflow model (threads, changelog, wiki upkeep)
- `D:\Obsidian\jmsl\CLAUDE.md` — vault map (cross-cutting gotchas, project list, structural conventions)

## Development Commands

```bash
flutter pub get
flutter test
flutter analyze
dart format .
```

The `benchmark/` and `example/` directories are runnable Flutter projects rooted at this repo.

## Logging & Workflow

All work across all projects is logged in the vault's central changelog: `D:\Obsidian\jmsl\changelog.md`

- Format: `- \`HH:MM\` \`[zero_cached_image]\` **TYPE** — Description`
- Types: `BUG FIX` | `FEATURE` | `FRICTION` | `DOC UPDATE` | `DECISION` | `GOTCHA` | `REFACTOR` | `DEPLOY`
- Log **as units of work close** — append to changelog before moving to the next ask. Don't batch a whole session into one trailing entry. Multi-step iteration on a coherent topic = open a thread folder mid-session at `D:\Obsidian\jmsl\threads\<slug>\`, close it with `report.md` when done.
- **First action in every conversation**: read `D:\Obsidian\jmsl\threads.md` and register what you're working on, with a `[claude.md]` source marker. See `D:\Obsidian\jmsl\wiki\workflow.md` for the full model.
- **No scratch files in this repo.** Any new artifact (HTML mockup, draft script, screenshot, scratch doc, throwaway log) lives in `D:\Obsidian\jmsl\threads\<slug>\files\`, never at this repo root or any subfolder. If no thread exists, open one first.

After completing work, update the relevant wiki pages — knowledge gaps are bugs; close them in the same task.

## Conventions

- Do not create services. If unsure where code belongs, ask.
- This is a published package. Public-API changes need a CHANGELOG entry and a thoughtful semver bump (additive constructor params are MINOR; rename / remove is MAJOR).
- The `extensionAllowlist` + `cacheDirName` knobs exist so `zero_cached_video` can reuse `ZeroCacheManager` without forking. If you tighten them, check `D:\Github\zero_cached_video\lib\src\zero_video_cache_manager.dart` still works.
