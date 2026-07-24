#!/bin/bash
# Thin wrapper — the real logic lives in setup-claude.sh.
# Creates "Claude Home" (strong blue, orange "H" badge, profile ~/.claude-desktop-home).
exec "$(dirname "$0")/setup-claude.sh" Home 0A66FF H FF8C42 0.65
