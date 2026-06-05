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
    if [ -d "$cache/.git" ]; then
        git -C "$cache" pull --ff-only
    else
        git clone --depth 1 https://github.com/dnsmalla/skills.git "$cache"
    fi
    central="$cache"
fi

echo "central skills repo: $central"
"$central/scripts/sync-runtime.sh" "$TARGET"
echo "InfiniteBrain runtime skills refreshed from central."
