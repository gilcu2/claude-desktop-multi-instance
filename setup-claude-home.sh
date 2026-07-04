#!/bin/bash
# Thin wrapper — the real logic lives in setup-claude.sh.
# Creates "Claude Home" (blue, badge "H", profile ~/.claude-desktop-home).
exec "$(dirname "$0")/setup-claude.sh" Home 4A7CFE H
