# Data model

## Note (markdown file, source of truth)

See `Resources/rules/output-format.mdc` for the canonical frontmatter.

## Sidecar SQLite (`.infinitebrain/index.db`)

```sql
CREATE TABLE notes (
    id            TEXT PRIMARY KEY,
    type          TEXT NOT NULL,
    title         TEXT NOT NULL,
    summary       TEXT NOT NULL,
    content_hash  TEXT NOT NULL,
    version       INTEGER NOT NULL,
    file_path     TEXT NOT NULL,
    updated_at    INTEGER NOT NULL
);

CREATE TABLE edges (
    src_id        TEXT NOT NULL,
    type          TEXT NOT NULL,
    dst_id        TEXT NOT NULL,
    evidence      TEXT,
    PRIMARY KEY (src_id, type, dst_id)
);

CREATE TABLE embeddings (
    note_id       TEXT PRIMARY KEY,
    dim           INTEGER NOT NULL,
    vector        BLOB NOT NULL,
    model         TEXT NOT NULL
);

CREATE TABLE ingest_checkpoint (
    file_id       TEXT NOT NULL,
    unit_index    INTEGER NOT NULL,
    stage         TEXT NOT NULL,
    status        TEXT NOT NULL,        -- ok | failed | quarantined
    ts            INTEGER NOT NULL,
    PRIMARY KEY (file_id, unit_index, stage)
);

CREATE VIRTUAL TABLE notes_fts USING fts5(id, title, summary, body);
```

The DB is rebuildable from the markdown files alone. Deleting it triggers a
full re-index on next launch.
