#!/bin/bash
# Thin wrapper — the real logic lives in setup-claude.sh.
# Creates "Claude Work" (orange, badge "W", profile ~/.claude-desktop-work).
exec "$(dirname "$0")/setup-claude.sh" Work FF8C42 W
