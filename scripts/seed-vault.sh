#!/usr/bin/env bash
# Initialises an empty vault folder with the directory layout InfiniteBrain expects.
set -euo pipefail

VAULT="${1:-./MyBrain}"
mkdir -p "${VAULT}/inbox" "${VAULT}/notes" "${VAULT}/.infinitebrain/skills" "${VAULT}/.infinitebrain/rules" "${VAULT}/.infinitebrain/quarantine"
echo "initialised vault at ${VAULT}"
