# rect_dev — Agent Instructions

Dev + agent tooling for [rect](../rect). **Read `../rect/CLAUDE.md` first** — it
carries the shared knowledge (toolchain paths, transport architecture,
in-process host recipe, quality gates, the "don't write slop" list). This file
covers only what's specific to rect_dev.

## What lives here (and why separate)

rect_dev holds the code that *runs, connects to, and drives* a rect app — and,
soon, the MCP server. It must **never** be a dependency of a shipped app, same
rule as `mob_dev`. The agent harness is split deliberately: the
introspection/drive surface (`Rect.Test`) lives in `rect` so it's RPC-able on
the running node; the client side (connect, run, dashboard, MCP) lives here.

Desktop makes this layer far lighter than mobile: the node is local, so there's
no adb/simctl device discovery and no EPMD tunnel setup that dominate `mob_dev`.

## Tasks

| Task | What it does |
|------|--------------|
| `mix rect.run` | Boot the current rect project as a named distributed node, open its windows (via `RectDev.Boot`), launch the native renderer. `--headless` skips the window. |
| `mix rect.connect` | `iex --remsh` into a running rect node — the dev/agent front door. |

`RectDev.Boot.run/0` is the boot helper the run task evals inside the fresh
node; it reads `config :rect, :app` and launches the renderer from
`RECT_RENDERER` or the prebuilt app in the rect dep.

## Toolchain / quality

Same as rect — see `../rect/CLAUDE.md`. In short:

```bash
export PATH="/Users/kevin/.local/share/mise/installs/erlang/29.0/bin:/Users/kevin/.local/share/mise/installs/elixir/1.20.0-otp-29/bin:$PATH"
mix test && mix format && mix credo --strict && mix compile --warnings-as-errors
```

rect_dev depends on `rect` via `path: "../rect"`, so it needs rect checked out as
a sibling (CI does a second checkout). No Erlang source here → no erlfmt step.

## Follow-ups

- **rect_mcp**: `rect_new` emits `.mcp.json` pointing at `rect_mcp.server`. Fold
  the MCP server in here first (typed tools backed by RPC into the BEAM,
  mirroring the planned `mob_mcp`); split a separate `rect_mcp` package only if
  it grows.
- **GUI host launch**: `mix rect.run` currently launches the socket renderer.
  Add a mode that builds/launches the in-process `rect_host` once its GUI layer
  lands (see `../rect/CLAUDE.md`).
