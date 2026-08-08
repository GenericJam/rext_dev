defmodule Mix.Tasks.Rext.Release do
  @shortdoc "Build a self-contained release + native renderer + launcher"
  @moduledoc """
  Package the current rext app for distribution: a BEAM release (bundled ERTS,
  no separate Erlang install needed on the target machine), the native renderer
  built self-contained (no separate .NET install needed either), and a launcher
  that starts the release, waits for the bridge, shows the window, and stops the
  release again once the window closes.

      mix rext.release

  Windows-only for now — WinForms (`native/windows`) is the only native backend
  that self-contained-publishes into one portable executable; the Compose
  backend targets a JVM and has no jlink/jpackage story yet (see `PLAN.md`).

  ## Output

  Under `_build/prod/rel/<app>/`, alongside the normal `mix release` output:

    * `renderer/rext_renderer.exe` — the self-contained WinForms renderer
    * `bin/launcher.ps1` — starts the release, polls the bridge port, launches
      the renderer, stops the release when the renderer exits
    * `bin/run.bat` — double-click entry point (`.ps1` files don't run on
      double-click, so this just shells out to the launcher)

  ## Known limitation

  The launcher pins `REXT_PORT` to a fixed port rather than reading back the
  bridge's actual (possibly fallen-back, see `Rext.Bridge`) port, so only one
  instance can run at a time. A port-file handshake removes this; not yet built.
  """
  use Mix.Task

  alias RextDev.Release

  @impl true
  def run(_argv) do
    Mix.Task.run("compile")

    app = Mix.Project.config()[:app]
    window_id = primary_window!()

    build_release!()
    build_renderer!(app)
    write_launcher!(app, window_id)
    Release.clean_stray_artifacts!(Release.release_root(app))

    Mix.shell().info("""

    Release + renderer ready: #{Release.release_root(app)}\\
    Run it:  #{Release.release_root(app)}\\bin\\run.bat
    """)
  end

  defp primary_window! do
    case Application.get_env(:rext, :app) do
      nil -> Mix.raise("no app configured — set `config :rext, :app, MyApp`")
      app_module -> RextDev.Boot.primary_window(app_module)
    end
  end

  defp build_release! do
    Mix.shell().info("[rext.release] mix release --overwrite (MIX_ENV=prod)")

    {_io, status} =
      System.cmd("mix", ["release", "--overwrite"],
        env: [{"MIX_ENV", "prod"}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("mix release failed (exit #{status})")
  end

  defp build_renderer!(app) do
    src = Release.renderer_source(Mix.Project.deps_paths())
    out = Path.expand(Release.renderer_dir(app))

    Mix.shell().info("[rext.release] dotnet publish (self-contained, single-file) — #{src}")

    {_io, status} =
      System.cmd(
        "dotnet",
        [
          "publish",
          "-c",
          "Release",
          "-r",
          "win-x64",
          "--self-contained",
          "true",
          "-p:PublishSingleFile=true",
          "-o",
          out
        ],
        cd: src,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("dotnet publish failed (exit #{status})")
  end

  defp write_launcher!(app, window_id) do
    bin = Path.join(Release.release_root(app), "bin")
    File.mkdir_p!(bin)
    File.write!(Path.join(bin, "launcher.ps1"), Release.launcher_ps1(app, window_id))
    File.write!(Path.join(bin, "run.bat"), Release.run_bat())
  end
end
