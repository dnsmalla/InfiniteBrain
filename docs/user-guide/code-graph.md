# Code Graph

The Code Graph tab visualizes the structure of a code repository as an interactive graph using the external [Graphify](https://github.com/safishamsi/graphify) CLI.

## Install Graphify

InfiniteBrain shells out to `graphify`. Install it once:

```bash
uv tool install graphifyy
```

(Note: package name is `graphifyy` with a double-y; binary is `graphify`.)

## Usage

1. Open **Code Graph** in the sidebar.
2. Click the folder button to pick a repository.
3. Click **Run Graphify**.
4. Click a node to select it; double-click to open the underlying file.

## Caching

Each folder's last graph is cached at `~/Library/Application Support/InfiniteBrain/CodeGraph/<hash>/`. Re-running overwrites.

## Troubleshooting

- **"Graphify not installed"** — click the copy-install-command button and run it in a terminal.
- **"Unsupported graphify schema vN"** — your installed `graphify` produces a JSON schema this build doesn't support. Pin `graphify` to a compatible version or upgrade InfiniteBrain.
