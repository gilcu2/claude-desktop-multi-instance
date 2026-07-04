# Claude Desktop — multiple accounts on macOS

Run several **Claude Desktop** accounts at the same time on macOS, each as a
fully independent app that you can tell apart at a glance — distinct **name**,
**icon**, **process**, and **window title**.

macOS normally only lets you run one instance of Claude Desktop, and even tricks
to launch a second copy leave every window labelled just "Claude" in the menu
bar, Dock, ⌘-Tab switcher, and taskbar apps. This project builds a separate,
self-contained copy of the app per profile so every one of those surfaces shows
the profile's own name.

> Unofficial. Not affiliated with or endorsed by Anthropic. It never modifies
> your installed `/Applications/Claude.app` — it makes independent copies.

---

## What you get

For a profile called e.g. `Work`, you get:

| Surface | Shows |
|---|---|
| Menu bar (app menu) | **Claude Work** |
| Dock / Finder / ⌘-Tab | **Claude Work** + a tinted, letter-badged icon |
| Process / Activity Monitor | **Claude Work** |
| Window title (what taskbar apps read) | **Claude — Work** |
| Data (chats, logins, settings) | isolated in `~/.claude-desktop-work` |

Each profile is a real app at `~/Applications/Claude <name>.app` that you launch
like anything else (double-click, Spotlight, pin to the Dock). They run
simultaneously and stay signed into different accounts.

---

## Requirements

- macOS (tested on macOS 26, Apple Silicon) with an **APFS** home volume
- **Claude Desktop** installed at `/Applications/Claude.app`
- `node` (for the window-title patch; the script auto-installs `@electron/asar`)
- `python3` (Pillow is auto-installed if missing) for the icon tinting

## Usage

```bash
chmod +x setup-claude.sh
./setup-claude.sh <name> [tint-hex] [badge-letter]
```

- `<name>` — profile name, shown as `Claude <name>` (required). e.g. `Work`, `"Client A"`
- `[tint-hex]` — icon tint, 6 hex digits with or without `#` (default `4A7CFE` blue)
- `[badge-letter]` — one character drawn on the icon (default: first letter of the name)

Examples:

```bash
./setup-claude.sh Work FF8C42 W      # orange, "W" badge
./setup-claude.sh Home 4A7CFE H      # blue, "H" badge
./setup-claude.sh Personal 34C759    # green, auto "P" badge
./setup-claude.sh "Client A" AF52DE C
```

`setup-claude-work.sh` and `setup-claude-home.sh` are thin convenience wrappers
that just call `setup-claude.sh` with preset arguments.

First launch of each profile: sign in with that account. If a `claude://` login
link opens the wrong window, quit the others first so the link routes correctly.

---

## How it works

Claude Desktop is an Electron app. The script clones it and changes each identity
surface independently, because macOS reads each from a different place:

1. **APFS clone** (`cp -c`) of `Claude.app` to `~/Applications/Claude <name>.app`.
   Copy-on-write, so it's instant and uses almost no extra disk. The original app
   is never touched.
2. **`CFBundleName` → `Claude <name>`.** This is what Electron shows in the **menu
   bar** (`app.name` reads `CFBundleName` on macOS). `CFBundleDisplayName` alone
   only changes the Finder/Dock label, not the menu bar.
3. **Helper apps renamed** to `Claude <name> Helper*.app`. Electron derives the
   helper-app path from `CFBundleName`; if they don't match it dies at launch with
   *"Unable to find helper app"*.
4. **Unique `CFBundleIdentifier`** (`…claudefordesktop.<slug>`) so macOS treats it
   as a separate app — its own Dock icon, and it can run alongside the others.
5. **Tinted, badged icon** written under a unique filename (so the macOS icon
   cache can't keep serving the old icon).
6. **Executable renamed + wrapped.** The real Electron binary keeps the clean
   per-profile name (so the **process name** taskbars read is distinct), and a
   tiny launcher wrapper becomes `CFBundleExecutable` and re-execs it with this
   profile's `--user-data-dir` — that's what isolates the data and lets a plain
   double-click use the right profile.
7. **Window-title patch** (`patch-title.js`). Taskbar apps (e.g. the third-party
   *Taskbar*) label buttons by the **window title**, which Claude's web content
   sets to just "Claude" for every instance. A small main-process hook is injected
   into `app.asar` that keeps each window's title suffixed with the profile name
   (`Claude — Work`). Because Claude enforces **asar integrity** (a SHA-256 of
   `app.asar` stored in `Info.plist`), the patcher recomputes that hash and
   preserves the native unpacked binaries (`.node` / `.dylib` / `spawn-helper`).
8. **Ad-hoc re-sign** with the `allow-jit` entitlement + hardened runtime.
   Modifying the bundle invalidates Apple's signature; without re-signing (and
   without `allow-jit`) Electron's V8 traps at startup under macOS's code-signing
   monitor.
9. **Cache refresh** — re-register with Launch Services and clear the icon cache.

## Files

| File | Purpose |
|---|---|
| `setup-claude.sh` | The engine — does everything above. |
| `patch-title.js` | Injects the window-title hook and fixes the asar integrity hash. |
| `setup-claude-work.sh` / `setup-claude-home.sh` | Preset wrappers around `setup-claude.sh`. |
| `package.json` | Declares the one dependency (`@electron/asar`). |

## Uninstall a profile

```bash
rm -rf "~/Applications/Claude Work.app" ~/.claude-desktop-work
```

## Caveats

- **Ad-hoc signing.** Each copy is re-signed locally, so on first launch macOS may
  re-prompt for permissions (camera, mic, screen, etc.) per profile.
- **Re-run after Claude updates.** Updates replace `/Applications/Claude.app`, not
  your copies. Re-run the script for each profile to rebuild them on the new
  version (the window-title patch in particular must be reapplied).
- Uses documented macOS tooling (`codesign`, `PlistBuddy`, `iconutil`,
  `@electron/asar`); no private APIs. Still, it modifies an app bundle — use at
  your own risk.

## License

MIT
