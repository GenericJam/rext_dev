defmodule Mix.Tasks.Rext.Installer do
  @shortdoc "Build a conventional Windows installer (Inno Setup) for the current app"
  @moduledoc """
  Package the current rext app as a real Windows installer: runs
  `mix rext.release` (release + self-contained renderer + launcher), then
  wraps that output in an Inno Setup installer — Start Menu shortcut, optional
  desktop shortcut, an uninstaller that stops the release before removing
  files (so it can't orphan a running `erl.exe`), proper "Apps & Features"
  registration.

      mix rext.installer
      mix rext.installer --publisher "My Company"
      mix rext.installer --version 1.2.3   # overrides mix.exs's version

  Windows-only, same as `mix rext.release` — see its moduledoc for what it
  produces. Requires Inno Setup's command-line compiler on PATH
  (`choco install innosetup`); this task shells out to it (`ISCC.exe`), it
  doesn't reimplement it.

  ## Cold path only

  This installer is for the *cold* path only: a fresh install, or any update
  that touches native code (the renderer, the NIF, an ERTS bump) — see
  `PLAN.md`'s "Distribution" section. Pure-BEAM-code hot updates are a
  separate, not-yet-built mechanism (OTP's own appup/relup/release_handler),
  deliberately outside this task's job.

  ## Known limitation

  `AppId` is derived deterministically from the app name (see
  `RextDev.Release.app_guid/1`) so re-running this against the same app
  produces an installer Windows recognizes as an upgrade of the same
  product — but there's no code-signing here, so Windows SmartScreen will
  still flag the installer as from an "unknown publisher" until it's signed.
  """
  use Mix.Task

  alias RextDev.Release

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [publisher: :string, version: :string])

    Mix.Task.run("rext.release")

    app = Mix.Project.config()[:app]
    version = opts[:version] || Mix.Project.config()[:version]
    publisher = opts[:publisher] || Release.display_name(app)

    iss_path = write_iss!(app, version, publisher)
    installer_path = compile!(iss_path, app, version)

    Mix.shell().info("\nInstaller ready: #{installer_path}")
  end

  defp write_iss!(app, version, publisher) do
    dir = Release.installer_output_dir()
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{app}.iss")
    File.write!(path, Release.installer_iss(app, version, publisher))
    path
  end

  defp compile!(iss_path, app, version) do
    iscc = find_iscc!()
    Mix.shell().info("[rext.installer] #{iscc} #{iss_path}")

    {_io, status} =
      System.cmd(iscc, [iss_path], into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0, do: Mix.raise("ISCC.exe failed (exit #{status})")

    Path.join(Release.installer_output_dir(), "#{app}-#{version}-setup.exe")
  end

  defp find_iscc! do
    System.find_executable("iscc") || System.find_executable("ISCC") ||
      well_known_iscc_path() ||
      Mix.raise("""
      Inno Setup's ISCC.exe not found on PATH.
      Install it: choco install innosetup
      """)
  end

  defp well_known_iscc_path do
    path = "C:/Program Files (x86)/Inno Setup 6/ISCC.exe"
    if File.exists?(path), do: path
  end
end
