defmodule RextDev.Boot do
  @moduledoc """
  Boot helper invoked by `mix rext.run` inside a freshly-named distributed VM.

  Opens the app's windows, then launches the native render backend for the app's
  primary window — building the renderer first if it isn't built yet, so
  `mix rext.run` is a genuine one-command launch. Kept out of `rext` (the runtime
  lib) because launching/building the renderer is a dev-only concern that must
  never be a dependency of a shipped app.
  """
  require Logger

  @doc "Open the configured app's windows and launch the render backend."
  @spec run() :: :ok
  def run do
    case Application.get_env(:rext, :app) do
      nil ->
        Logger.error("[rext.run] no app configured — set `config :rext, :app, MyApp`")

      app ->
        Rext.boot(app)
        Logger.info("[rext.run] booted #{inspect(app)} windows")
        maybe_launch_renderer(primary_window(app))
    end

    :ok
  end

  @doc false
  @spec primary_window(module()) :: String.t()
  def primary_window(app) do
    case app.windows() do
      [{_mod, opts} | _] -> to_string(opts[:id] || "main")
      _ -> "main"
    end
  end

  defp maybe_launch_renderer(window_id) do
    cond do
      System.get_env("REXT_HEADLESS") == "1" ->
        Logger.info("[rext.run] headless — skipping render backend")

      bin = resolve_renderer() ->
        launch_renderer(bin, window_id)

      true ->
        Logger.warning("[rext.run] render backend unavailable; running headless")
    end
  end

  defp launch_renderer(bin, window_id) do
    app = app_bundle(bin)
    port = Integer.to_string(Rext.Bridge.port())
    log = Path.join(System.tmp_dir!(), "rext_renderer.log")

    # Launch the .app through LaunchServices (`open`), NOT by exec'ing the inner
    # binary. A GUI app spawned as a BEAM port child runs under the BEAM's
    # erl_child_setup — outside the user's GUI (Aqua) session — and crashes deep
    # in the WindowServer (SkyLight) on NSApplication init. `open` runs it in
    # the right session. `--env` passes the handshake vars; `--stderr` captures
    # the renderer's log for diagnosis.
    #
    # `-W` blocks until the app quits, giving the lifecycle signal: close the
    # window → app exits → halt the BEAM, so `mix rext.run` leaves no residual.
    spawn(fn ->
      Logger.info(
        "[rext.run] launched render backend (via open) for window #{inspect(window_id)}"
      )

      {out, status} =
        System.cmd("open", open_args(app, port, window_id, log), stderr_to_stdout: true)

      if out != "", do: IO.write(out)
      Logger.info("[rext.run] render backend exited (#{status}); log: #{log} — shutting down")
      System.halt(0)
    end)
  end

  @doc false
  # The exact `open` invocation that launches the renderer through LaunchServices
  # (see launch_renderer/2 for why exec-ing the binary directly crashes). `-W`
  # is load-bearing for the lifecycle; the app path must come last.
  @spec open_args(String.t(), String.t() | integer(), String.t(), String.t()) :: [String.t()]
  def open_args(app, port, window_id, log) do
    [
      "-n",
      "-W",
      "--stderr",
      log,
      "--env",
      "REXT_PORT=#{port}",
      "--env",
      "REXT_WINDOW=#{window_id}",
      app
    ]
  end

  @doc false
  # .../RextRenderer.app/Contents/MacOS/rext_renderer → .../RextRenderer.app
  @spec app_bundle(String.t()) :: String.t()
  def app_bundle(bin), do: bin |> Path.dirname() |> Path.dirname() |> Path.dirname()

  # Locate the renderer binary, building it once if it hasn't been built yet.
  # Returns the path, or nil if it can't be found or built.
  defp resolve_renderer do
    case System.get_env("REXT_RENDERER") do
      path when is_binary(path) ->
        # A user-specified path is used as-is (we don't build someone else's binary).
        if File.exists?(path), do: path

      _ ->
        bin = default_renderer()

        cond do
          is_nil(bin) -> nil
          File.exists?(bin) and not stale?(bin) -> bin
          true -> build_renderer(bin)
        end
    end
  end

  @doc false
  # The built binary is stale if the Swift source has been edited since. Rebuild
  # on the next run so renderer changes are picked up without a manual step.
  # NB: keep the `..` segments unexpanded — the path runs through a path-dep
  # symlink, which the OS resolves correctly but `Path.expand/1` (lexical) does
  # not. If the source can't be found, treat as not-stale (use the built binary).
  @spec stale?(String.t()) :: boolean()
  def stale?(bin) do
    src = Path.join(Path.dirname(bin), "../../../main.swift")

    case {File.stat(src, time: :posix), File.stat(bin, time: :posix)} do
      {{:ok, s}, {:ok, b}} -> s.mtime > b.mtime
      _ -> false
    end
  end

  defp build_renderer(bin) do
    # Unexpanded on purpose — the path crosses a path-dep symlink (see stale?/1).
    script = Path.join(Path.dirname(bin), "../../../build.sh")

    if File.exists?(script) do
      Logger.info("[rext.run] building render backend (#{script})…")

      case System.cmd("bash", [script], stderr_to_stdout: true) do
        {_out, 0} -> if File.exists?(bin), do: bin
        {out, code} -> Logger.warning("[rext.run] renderer build failed (#{code}):\n#{out}")
      end
    else
      Logger.warning("[rext.run] no renderer and no build script at #{script}")
      nil
    end
  end

  # The prebuilt macOS renderer inside the rext dependency.
  defp default_renderer do
    case :code.priv_dir(:rext) do
      {:error, _} ->
        nil

      dir ->
        Path.join([
          to_string(dir),
          "..",
          "native",
          "macos",
          "RextRenderer.app",
          "Contents",
          "MacOS",
          "rext_renderer"
        ])
    end
  end
end
