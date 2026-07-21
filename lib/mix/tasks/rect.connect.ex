defmodule Mix.Tasks.Rect.Connect do
  @shortdoc "Open an IEx remote shell into a running rect node"
  @moduledoc """
  Connect an interactive IEx session into a running rect app over Erlang
  distribution — the dev/agent front door.

      mix rect.connect
      mix rect.connect --node myapp@127.0.0.1 --cookie mysecret

  Desktop makes this trivial compared to mob: the node is local, so there's no
  adb/simctl device discovery and no EPMD tunnel setup — just a `--remsh`.

  Once connected you have the full node: inspect windows with `Rect.Test`, hot
  push modules with `r/1` / `IEx.Helpers`, RPC into any process.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [node: :string, cookie: :string])

    app = Mix.Project.config()[:app]
    target = opts[:node] || "#{app}@127.0.0.1"
    cookie = opts[:cookie] || "rect_secret"

    cmd =
      "iex --name rect_console_#{:erlang.unique_integer([:positive])}@127.0.0.1 " <>
        "--cookie #{cookie} --remsh #{target}"

    Mix.shell().info("[rect.connect] #{cmd}")
    Mix.shell().cmd(cmd)
  end
end
