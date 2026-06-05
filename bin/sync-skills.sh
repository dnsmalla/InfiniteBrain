#!/usr/bin/env bash
# Refresh InfiniteBrain's bundled runtime skills FROM the central skills repo.
#
# Skills are authored centrally in dnsmalla/skills (the `runtime/` family), NOT
# here. This script mirrors that family into Sources/InfiniteBrainCore/Resources/skills
# so the SPM bundle + each vault's .infinitebrain/skills stay in sync with central.
#
# Central repo is located via, in order:
#   1. $SKILLS_REPO (path to a checkout)
#   2. ~/skills  (canonical clone; then ~/Desktop/skills for back-compat)
#   3. a cached clone of https://github.com/dnsmalla/skills.git
#
# Reproducible builds: set SKILLS_REF=<tag|branch|sha> to pin (used when central
# is resolved via the cached clone — e.g. in CI). Every sync records the synced
# central commit in .skills-lock so a build can be reproduced.
#
# Usage:  bin/sync-skills.sh
set -euo pipefail

cd "$(dirname "$0")/.."
TARGET="$PWD/Sources/InfiniteBrainCore/Resources/skills"

central=""
if [ -n "${SKILLS_REPO:-}" ] && [ -d "$SKILLS_REPO/runtime" ]; then
    central="$SKILLS_REPO"
elif [ -d "$HOME/skills/runtime" ]; then
    central="$HOME/skills"
elif [ -d "$HOME/Desktop/skills/runtime" ]; then
    central="$HOME/Desktop/skills"
else
    cache="$HOME/.cache/dnsmalla-skills"
    if [ ! -d "$cache/.git" ]; then
        git clone --depth 1 https://github.com/dnsmalla/skills.git "$cache"
    fi
    ref="${SKILLS_REF:-main}"
    git -C "$cache" fetch --depth 1 --tags origin "$ref" 2>/dev/null || git -C "$cache" fetch --depth 1 origin
    git -C "$cache" checkout -q "$ref" 2>/dev/null || git -C "$cache" checkout -q FETCH_HEAD
    central="$cache"
fi

echo "central skills repo: $central"
"$central/scripts/sync-runtime.sh" "$TARGET"
git -C "$central" rev-parse HEAD > "$PWD/.skills-lock" 2>/dev/null || true
echo "InfiniteBrain runtime skills refreshed from central @ $(cut -c1-9 "$PWD/.skills-lock" 2>/dev/null)."
