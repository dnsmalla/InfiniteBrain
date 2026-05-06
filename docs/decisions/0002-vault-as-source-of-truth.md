# 2. Vault as source of truth

Date: 2026-05-06

## Status

Accepted

## Context

The app produces Obsidian-compatible markdown. We could store canonical data
in a database and treat markdown as an export, or treat the vault as the
canonical store.

## Decision

The vault on disk is the source of truth. The SQLite sidecar at
`.infinitebrain/index.db` is a rebuildable cache (embeddings, FTS,
checkpoints).

## Consequences

- Users can edit notes in Obsidian and the app re-syncs from the vault.
- Backups are just `git commit` on the vault directory.
- Deleting the sidecar is non-destructive; the app re-indexes on launch.
- Every write must update both the file and the sidecar atomically (we use
  a write-ahead log under `.infinitebrain/wal/`).
