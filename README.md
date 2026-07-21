# rect_dev

Dev + agent tooling for [rect](https://github.com/GenericJam/rect) — a
BEAM-on-desktop UI framework for Elixir. Never a dependency of a shipped app;
this is the layer that runs, connects to, and (soon) exposes an MCP server over
a running rect application.

Add it as a dev dependency alongside `rect`:

```elixir
# mix.exs
{:rect, "~> 0.1"},
{:rect_dev, "~> 0.1", only: :dev, runtime: false}
```

## Tasks

| Task | Purpose |
|------|---------|
| `mix rect.run` | Boot the current rect project as a named distributed node, open its windows, and launch the native renderer. |
| `mix rect.connect` | Open an IEx remote shell into a running rect node — the dev/agent front door. |

## Why a separate package

Same reason mob splits `mob_dev`: deploy/run/connect/dashboard/MCP code must
never end up as a dependency of the distributed `.app`. On desktop the dev loop
is far lighter than mobile (local dist, no device discovery, no tunnels), but
the separation still matters for a clean shipped artifact.

The agent harness itself is split deliberately: the introspection/drive surface
(`Rect.Test`, and the native tree-walk) lives in `rect` so it's RPC-able on the
running node; the *client* side (connect, dashboard, MCP) lives here.

See `CLAUDE.md` for the full picture.
