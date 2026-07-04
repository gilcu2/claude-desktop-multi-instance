#!/bin/bash
# Create an independent, named Claude Desktop instance that shows its OWN name
# in the menu bar / Dock / app switcher and keeps its own isolated profile —
# so you can run several accounts at once and tell them apart.
#
# Usage:
#   ./setup-claude.sh <name> [tint-hex] [badge-letter]
#
#   <name>         Profile name. Shown as "Claude <name>". Required.
#                  e.g. Work, Home, Personal, "Client A"
#   [tint-hex]     Icon tint, 6-digit hex (with or without #). Default: 4A7CFE.
#                  e.g. FF8C42 (orange), 4A7CFE (blue), 34C759 (green)
#   [badge-letter] One character drawn on the icon. Default: first letter of name.
#
# What it does (and why each step is needed):
#   * APFS-clones /Applications/Claude.app (instant, copy-on-write). The real
#     app is never touched or re-signed.
#   * CFBundleName -> "Claude <name>"  — THIS is what Electron shows in the menu
#     bar (app.name reads CFBundleName on macOS). CFBundleDisplayName alone is
#     NOT enough; it only changes the Finder/Dock label, not the menu bar.
#   * Renames the four "Claude Helper*.app" bundles to "Claude <name> Helper*"
#     — Electron derives the helper path from CFBundleName, so they MUST match
#     or it dies at launch with "Unable to find helper app".
#   * Unique CFBundleIdentifier — separate Dock identity; runs alongside others.
#   * Tints the icon + adds a letter badge, saved under a UNIQUE filename so the
#     macOS icon cache can't serve the old icon.
#   * Wraps the executable so every launch uses this profile's --user-data-dir.
#   * Ad-hoc re-signs with allow-jit + hardened runtime (Electron's V8 traps at
#     startup otherwise on macOS 26's code-signing monitor).
#   * Forces Launch Services + the icon cache to refresh.
#
# Produces:
#   App bundle : ~/Applications/Claude <name>.app     (launch like any app)
#   Data dir   : ~/.claude-desktop-<slug>
#
# Run on macOS: chmod +x setup-claude.sh && ./setup-claude.sh Work

set -e

NAME="$1"
TINT_HEX="${2:-4A7CFE}"
BADGE_LETTER="$3"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <name> [tint-hex] [badge-letter]"
  echo "  e.g. $0 Work FF8C42 W"
  exit 1
fi

# Derive everything from <name>.
DISPLAY_NAME="Claude $NAME"
SLUG=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
[ -n "$SLUG" ] || { echo "Error: name '$NAME' produced an empty slug."; exit 1; }
DATA_DIR="$HOME/.claude-desktop-$SLUG"
BUNDLE_ID="com.anthropic.claudefordesktop.$SLUG"
[ -n "$BADGE_LETTER" ] || BADGE_LETTER=$(echo "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')

SRC_APP="/Applications/Claude.app"
COPY_APP="$HOME/Applications/${DISPLAY_NAME}.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse hex tint -> R G B, derive a darker badge fill (~55%).
TINT_HEX="${TINT_HEX#\#}"
if ! echo "$TINT_HEX" | grep -qiE '^[0-9a-f]{6}$'; then
  echo "Error: tint-hex '$TINT_HEX' must be 6 hex digits (e.g. FF8C42)."
  exit 1
fi
TR=$((16#${TINT_HEX:0:2})); TG=$((16#${TINT_HEX:2:2})); TB=$((16#${TINT_HEX:4:2}))
FR=$((TR * 55 / 100)); FG=$((TG * 55 / 100)); FB=$((TB * 55 / 100))

if [ ! -d "$SRC_APP" ]; then
  echo "Error: $SRC_APP not found. Is Claude Desktop installed?"
  exit 1
fi

echo "Creating \"$DISPLAY_NAME\"  (tint #$TINT_HEX, badge '$BADGE_LETTER', profile $DATA_DIR)"
mkdir -p "$HOME/Applications" "$DATA_DIR"
pkill -9 -f "${DISPLAY_NAME}.app" 2>/dev/null || true

echo "[1/8] APFS-cloning $SRC_APP (instant, copy-on-write)..."
rm -rf "$COPY_APP"
/bin/cp -c -R "$SRC_APP" "$COPY_APP"
xattr -cr "$COPY_APP" 2>/dev/null || true

echo "[2/8] Patching Info.plist (name shown in menu bar + unique bundle id)..."
PL="$COPY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$DISPLAY_NAME'" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PL"

echo "[3/8] Renaming helper apps to match (Electron finds them via CFBundleName)..."
FW="$COPY_APP/Contents/Frameworks"
oldIFS="$IFS"; IFS=$'\n'
for suffix in "" " (GPU)" " (Plugin)" " (Renderer)"; do
  old="$FW/Claude Helper$suffix.app"
  new="$FW/$DISPLAY_NAME Helper$suffix.app"
  [ -d "$old" ] || continue
  mv "$old" "$new"
  mv "$new/Contents/MacOS/Claude Helper$suffix" "$new/Contents/MacOS/$DISPLAY_NAME Helper$suffix"
  hpl="$new/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $DISPLAY_NAME Helper$suffix" "$hpl"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME Helper$suffix" "$hpl" 2>/dev/null || true
done
IFS="$oldIFS"

echo "[4/8] Tinting the icon + '$BADGE_LETTER' badge (unique filename beats the icon cache)..."
SRC_ICON=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$PL" 2>/dev/null)
case "$SRC_ICON" in *.icns) ;; *) SRC_ICON="$SRC_ICON.icns" ;; esac
SRC_ICON_PATH="$COPY_APP/Contents/Resources/$SRC_ICON"
NEW_ICON="icon-$SLUG.icns"
NEW_ICON_PATH="$COPY_APP/Contents/Resources/$NEW_ICON"
if [ -f "$SRC_ICON_PATH" ]; then
  WORKDIR=$(mktemp -d)
  if iconutil -c iconset "$SRC_ICON_PATH" -o "$WORKDIR/orig.iconset" 2>/dev/null; then
    python3 -c "import PIL" 2>/dev/null || pip3 install pillow --break-system-packages --quiet
    python3 <<PYEOF
import glob, os
from PIL import Image, ImageDraw, ImageFont
src_dir = "$WORKDIR/orig.iconset"
tint = ($TR, $TG, $TB, 255)
badge_fill = ($FR, $FG, $FB, 255)
badge_letter = "$BADGE_LETTER"
for path in glob.glob(os.path.join(src_dir, "*.png")):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    alpha = img.split()[3]
    overlay = Image.new("RGBA", (w, h), tint)
    tinted = Image.blend(img, overlay, 0.35)
    tinted.putalpha(alpha)
    badge_d = max(int(w * 0.42), 12)
    badge_img = Image.new("RGBA", (badge_d, badge_d), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge_img)
    draw.ellipse([0, 0, badge_d, badge_d], fill=badge_fill,
                 outline=(255, 255, 255, 255), width=max(badge_d // 20, 1))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", int(badge_d * 0.6))
    except Exception:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), badge_letter, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((badge_d - tw) / 2 - bbox[0], (badge_d - th) / 2 - bbox[1]),
              badge_letter, fill=(255, 255, 255, 255), font=font)
    tinted.paste(badge_img, (w - badge_d, h - badge_d), badge_img)
    tinted.save(path)
print("      tinted", len(glob.glob(os.path.join(src_dir, "*.png"))), "icon sizes")
PYEOF
    iconutil -c icns "$WORKDIR/orig.iconset" -o "$NEW_ICON_PATH"
    rm -f "$SRC_ICON_PATH"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $NEW_ICON" "$PL"
  else
    echo "      Note: couldn't decompose $SRC_ICON — leaving icon untinted."
  fi
  rm -rf "$WORKDIR"
else
  echo "      Warning: icon $SRC_ICON not found — leaving default icon."
fi

echo "[5/8] Naming the executable + baking the data dir into it (wrapper)..."
# Tools that label windows by the running PROCESS/executable name (e.g. the
# third-party "Task Bar" app) show the executable leaf, which is otherwise
# identical ("Claude") for every instance. So the real Electron binary KEEPS
# the clean per-profile name ("$DISPLAY_NAME") — that's the process you see —
# and a tiny launcher wrapper (which just re-execs it with this profile's
# --user-data-dir) takes a side name and becomes CFBundleExecutable.
# Electron finds its helpers via CFBundleName, not this name, so it's safe.
# Net result: bundle name, display name, bundle id, AND process name all differ.
M="$COPY_APP/Contents/MacOS"
OLD_EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PL")   # "Claude"
REAL_EXE="$DISPLAY_NAME"            # the Electron process you actually see
WRAP_EXE="$DISPLAY_NAME.launcher"   # CFBundleExecutable; execs REAL_EXE
mv "$M/$OLD_EXE" "$M/$REAL_EXE"
[ "$OLD_EXE" = "$REAL_EXE" ] || rm -f "$M/$OLD_EXE"
cat > "$M/$WRAP_EXE" <<EOF
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$DIR/$REAL_EXE" --user-data-dir="$DATA_DIR" "\$@"
EOF
chmod +x "$M/$WRAP_EXE"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $WRAP_EXE" "$PL"

echo "[6/8] Patching the window title -> \"… — $NAME\" (so window-title taskbars differ)..."
# Some taskbars (e.g. the third-party Taskbar app) label buttons by the WINDOW
# title, which Claude sets to "Claude" for every instance. This injects a hook
# so each window's title is suffixed with the profile name. Needs @electron/asar
# (installed next to this script). If unavailable, we skip it — the app name,
# icon, and process name are still distinct, just not the per-window title.
if ! ( cd "$SCRIPT_DIR" && node -e 'require("@electron/asar")' ) 2>/dev/null; then
  echo "      installing @electron/asar (one-time)..."
  ( cd "$SCRIPT_DIR" && npm install --silent @electron/asar@4 >/dev/null 2>&1 ) || true
fi
if [ -f "$SCRIPT_DIR/patch-title.js" ] && ( cd "$SCRIPT_DIR" && node -e 'require("@electron/asar")' ) 2>/dev/null; then
  node "$SCRIPT_DIR/patch-title.js" "$COPY_APP" "$NAME" || echo "      WARN: title patch failed; continuing without it"
else
  echo "      skipped (asar tool or patch-title.js unavailable) — window title stays \"Claude\"."
fi

echo "[7/8] Ad-hoc re-signing (allow-jit + hardened runtime), inside-out..."
ENT="$(mktemp -d)/ent.plist"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
PLIST
codesign --force --options runtime --sign - "$FW/Electron Framework.framework" >/dev/null 2>&1
codesign --force --options runtime --entitlements "$ENT" --sign - "$M/$REAL_EXE" >/dev/null 2>&1
for h in "$FW"/*.app; do
  codesign --force --options runtime --entitlements "$ENT" --sign - "$h" >/dev/null 2>&1
done
# main bundle last, NO --deep (so it doesn't strip entitlements off the wrapped binary)
codesign --force --options runtime --entitlements "$ENT" --sign - "$COPY_APP" >/dev/null 2>&1
if codesign --verify --deep --strict "$COPY_APP" 2>/dev/null; then
  echo "      signature valid."
else
  echo "      WARNING: signature verification failed — the app may not launch."
fi

echo "[8/8] Refreshing Launch Services + icon caches..."
touch "$COPY_APP"
[ -x "$LSREG" ] && "$LSREG" -f "$COPY_APP" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
killall Dock Finder iconservicesagent 2>/dev/null || true

echo ""
echo "Done."
echo "  App bundle : $COPY_APP   (shows as \"$DISPLAY_NAME\")"
echo "  Data dir   : $DATA_DIR"
echo ""
echo "Launch it like any app (double-click, Spotlight, or drag to the Dock)."
echo "It always uses its own profile, so it runs alongside the real Claude and"
echo "your other instances. First run: sign in with the account for this profile."
echo ""
echo "If the Dock/Finder still shows the old icon, it's just a stale cache: log"
echo "out and back in (or restart) once and it'll pick up the new one."
