# rext_dev

Dev + agent tooling for [rext](https://github.com/GenericJam/rext) — a
BEAM-on-desktop UI framework for Elixir. Never a dependency of a shipped app;
this is the layer that runs and connects to a running rext application.

Add it as a dev dependency alongside `rext`:

```elixir
# mix.exs
{:rext, "~> 0.1"},
{:rext_dev, "~> 0.1", only: :dev, runtime: false}
```

## Tasks

| Task | Purpose |
|------|---------|
| `mix rext.run` | Boot the current rext project as a named distributed node, open its windows, and launch the native renderer. |
| `mix rext.connect` | Open an IEx remote shell into a running rext node — the dev/agent front door. |

## Why a separate package

Same reason mob splits `mob_dev`: run/connect/dashboard code must
never end up as a dependency of the distributed `.app`. On desktop the dev loop
is far lighter than mobile (local dist, no device discovery, no tunnels), but
the separation still matters for a clean shipped artifact.

The agent harness itself is split deliberately: the introspection/drive surface
(`Rext.Test`, and the native tree-walk) lives in `rext` so it's RPC-able on the
running node; the *client* side (connect, dashboard) lives here.

See `CLAUDE.md` for the full picture.
