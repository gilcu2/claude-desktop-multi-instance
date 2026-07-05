# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS shell-script tool that clones `/Applications/Claude.app` into independent,
per-profile copies (`~/Applications/Claude <name>.app`) so multiple Claude Desktop
accounts can run simultaneously, each with its own name, icon, process, window
title, and data directory. It never modifies the original installed app.

## Commands

```bash
./setup-claude.sh <name> [tint-hex] [badge-letter]   # build/rebuild a profile
./setup-claude-work.sh                                # preset: Work, orange, "W"
./setup-claude-home.sh                                # preset: Home, blue, "H"
./share-claude-config.sh <name> <name> [more...]      # symlink select config between profiles
./build-changelog.sh <version>                        # collect newsfragments/ into CHANGELOG.md
npm install                                           # installs @electron/asar (used by patch-title.js)
```

There is no build, lint, or test suite — this is a two-file shell/node tool, run
directly and verified by launching the generated `.app`.

To uninstall a profile: `rm -rf "~/Applications/Claude <name>.app" ~/.claude-desktop-<name-lowercase>`.

## Architecture

Two files do all the work:

- **`setup-claude.sh`** — the engine. Given a profile name, it performs a sequence
  of independent identity-surface edits on an APFS clone of `Claude.app`, because
  macOS reads app identity from several different, unrelated places:
  1. APFS copy-on-write clone (`cp -c`) to `~/Applications/Claude <name>.app`.
  2. `CFBundleName` → `Claude <name>` (menu bar; `CFBundleDisplayName` alone is
     not enough — it only affects Finder/Dock).
  3. Helper apps renamed to match `CFBundleName`, or Electron fails at launch
     with "Unable to find helper app".
  4. Unique `CFBundleIdentifier` so macOS treats it as a distinct app.
  5. Tinted, badged icon written under a unique filename (icon cache busting).
  6. Real Electron binary renamed to the profile name (distinct process name);
     a small wrapper becomes `CFBundleExecutable` and re-execs it with
     `--user-data-dir` pointed at the profile's isolated data directory.
  7. Window-title patch applied via `patch-title.js`.
  8. Ad-hoc re-sign with `allow-jit` entitlement + hardened runtime (required
     because any bundle modification invalidates Apple's signature).
  9. Launch Services re-register + icon cache refresh.

- **`patch-title.js`** — injects a main-process hook into `app.asar` so each
  window's title stays suffixed with the profile name (e.g. `Claude — Work`),
  since Claude's web content otherwise sets every window's title to plain
  "Claude" (which is what third-party taskbar apps read to label buttons).
  Because Claude enforces asar integrity (a SHA-256 of `app.asar` in
  `Info.plist`), this script recomputes and updates that hash after patching,
  and preserves native unpacked binaries (`.node` / `.dylib` / `spawn-helper`).

`setup-claude-work.sh` / `setup-claude-home.sh` are one-line wrappers that just
call `setup-claude.sh` with fixed arguments.

- **`share-claude-config.sh`** — opt-in config sharing across profiles, modeled
  on how [jean-claude](https://github.com/MikeVeerman/jean-claude) syncs Claude
  Code's config: it moves a fixed set of known-safe files
  (`claude_desktop_config.json`, `extensions-blocklist.json`,
  `git-worktrees.json`, `cowork-enabled-cli-ops.json`) out of each named
  profile's data dir into `~/.claude-desktop-shared/` and symlinks them back,
  so editing one from any linked profile updates all the others. Deliberately
  excludes anything account-specific (`config.json`'s OAuth token cache,
  `buddy-tokens.json`, `ant-did`, cookies/session/local storage,
  `claude-code*`/`local-agent-mode-sessions`), so each profile keeps its own
  login and session state. Existing files are backed up to `*.bak` before
  being replaced with a symlink, and re-running is idempotent.

## Changelog

`CHANGELOG.md` is built from `newsfragments/` (see `newsfragments/README.md`)
via `build-changelog.sh`, rather than edited by hand. Any change worth
mentioning to a user should add a fragment file there.

## Things to keep in mind when editing

- Must be re-run per profile after every Claude Desktop app update, since
  updates replace `/Applications/Claude.app` but not the generated copies —
  the window-title patch in particular needs reapplying.
- Any change to the identity-surface steps in `setup-claude.sh` needs the
  ad-hoc re-sign step to still run afterward, or the modified bundle won't
  launch under macOS code-signing enforcement.
- `patch-title.js` must keep the asar integrity hash in `Info.plist` in sync
  with the patched `app.asar`, and must not touch the unpacked native binaries.
