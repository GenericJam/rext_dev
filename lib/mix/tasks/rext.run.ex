defmodule Mix.Tasks.Rext.Run do
  @shortdoc "Launch a rext app in a named distributed VM with the native renderer"
  @moduledoc """
  Start the current rext project as a named distributed node, open its windows,
  and launch the macOS render backend.

      mix rext.run
      mix rext.run --node myapp@127.0.0.1 --cookie mysecret
      mix rext.run --port 9000         # override the bridge port for this run
      mix rext.run --headless          # no native window (agent-only)

  The node is named so an agent or a second IEx can connect over dist and drive
  it with `Rext.Test` (see `mix rext.connect`). On desktop this is a local dist
  connection — no tunnels, no device discovery, unlike mob's mobile setup.

  ## Port

  `--port` sets the render-backend (bridge) port for this run, taking precedence
  over `config :rext, :port` and the compiled-in default. It's passed through as
  the `REXT_PORT` env var, which `Rext.Bridge.resolve_port/0` reads at boot. If
  the chosen port is busy, the bridge still falls back to an ephemeral port
  rather than failing.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          node: :string,
          cookie: :string,
          renderer: :string,
          headless: :boolean,
          port: :integer
        ]
      )

    app = Mix.Project.config()[:app]
    node = opts[:node] || "#{app}@127.0.0.1"
    cookie = opts[:cookie] || "rext_secret"

    env = [{"REXT_HEADLESS", if(opts[:headless], do: "1", else: "0")}]
    env = if opts[:renderer], do: [{"REXT_RENDERER", opts[:renderer]} | env], else: env
    env = if opts[:port], do: [{"REXT_PORT", Integer.to_string(opts[:port])} | env], else: env

    cmd =
      "elixir --name #{node} --cookie #{cookie} -S mix run --no-halt -e 'RextDev.Boot.run()'"

    Mix.shell().info("[rext.run] #{cmd}")
    # Runs in the foreground, inheriting the terminal's TTY. Ctrl-C stops it.
    Mix.shell().cmd(cmd, env: env)
  end
end
