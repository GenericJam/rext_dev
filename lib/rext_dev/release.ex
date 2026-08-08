defmodule RextDev.Release do
  @moduledoc """
  Pure helpers for `mix rext.release` — path resolution and the launcher
  template. Kept separate from the Mix task so the parts that don't shell out
  to `mix release`/`dotnet` are unit-testable.

  Windows-only for now: WinForms (`native/windows`) is the only native backend
  that self-contained-publishes into a single portable executable. The Compose
  backend targets a JVM and has no jlink/jpackage story yet (see PLAN.md).
  """

  @bridge_port 8137

  @doc "The release root Mix produces for `app` under `_build/prod/rel/`."
  @spec release_root(atom()) :: String.t()
  def release_root(app), do: Path.join(["_build", "prod", "rel", to_string(app)])

  @doc "Where the self-contained renderer gets published, inside the release root."
  @spec renderer_dir(atom()) :: String.t()
  def renderer_dir(app), do: Path.join(release_root(app), "renderer")

  @doc """
  The `native/windows` source dir inside the resolved `rext` dependency —
  wherever Mix put it (path dep in dev, a real fetch for a Hex/git dep).
  """
  @spec renderer_source(map()) :: String.t()
  def renderer_source(deps_paths), do: Path.join([deps_paths[:rext], "native", "windows"])

  @doc "Fixed bridge port the launcher and release agree on (see moduledoc note on `mix rext.release`)."
  @spec bridge_port() :: pos_integer()
  def bridge_port, do: @bridge_port

  @doc """
  Render the PowerShell launcher: starts the release, polls the bridge port,
  launches the renderer, then stops the release once the renderer exits.
  """
  @spec launcher_ps1(atom(), String.t()) :: String.t()
  def launcher_ps1(app, window_id) do
    """
    $ErrorActionPreference = "Stop"
    $releaseRoot = Split-Path -Parent $PSScriptRoot
    $env:REXT_PORT = "#{@bridge_port}"

    $release = Start-Process -FilePath "$releaseRoot\\bin\\#{app}.bat" -ArgumentList "start" `
      -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput "$releaseRoot\\release.out.log" `
      -RedirectStandardError "$releaseRoot\\release.err.log"

    $deadline = (Get-Date).AddSeconds(30)
    $up = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect("127.0.0.1", #{@bridge_port})
            $client.Close()
            $up = $true
            break
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }

    if (-not $up) {
        Write-Error "rext bridge did not come up on port #{@bridge_port} within 30s"
        Stop-Process -Id $release.Id -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $env:REXT_WINDOW = "#{window_id}"
    Start-Process -FilePath "$releaseRoot\\renderer\\rext_renderer.exe" -PassThru -Wait | Out-Null

    & "$releaseRoot\\bin\\#{app}.bat" stop
    """
  end

  @doc "The double-click entry point — `.ps1` files don't run on double-click, so shim through cmd."
  @spec run_bat() :: String.t()
  def run_bat do
    """
    @echo off
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1"
    """
  end

  @stray_artifacts ["release.out.log", "release.err.log", "bin/erl_crash.dump", "erl_crash.dump"]

  @doc """
  Delete runtime artifacts the launcher/BEAM leave behind in a release root
  from a prior local run (`release.out.log`/`.err.log` from `launcher_ps1`'s
  redirects, `erl_crash.dump` from a crashed BEAM) — anyone packaging this
  directory further (an installer, a plain zip) would otherwise ship them.
  Idempotent: missing files are silently skipped.
  """
  @spec clean_stray_artifacts!(String.t()) :: :ok
  def clean_stray_artifacts!(release_root) do
    for rel <- @stray_artifacts, do: File.rm(Path.join(release_root, rel))
    :ok
  end

  @doc "Where `mix rext.installer` writes the generated .iss and compiled setup.exe — a sibling of `rel/`, never inside it (the installer output must not end up inside its own [Files] source tree)."
  @spec installer_output_dir() :: String.t()
  def installer_output_dir, do: Path.join(["_build", "prod", "installer"])

  @doc "Humanize an app atom into a display name: :rext_demo -> \"Rext Demo\"."
  @spec display_name(atom()) :: String.t()
  def display_name(app) do
    app
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  A GUID-shaped, stable-per-app identifier for Inno Setup's `AppId` (its
  upgrade-detection key across installer runs). Not a real UUID (no
  version/variant bits set) — Inno doesn't care, it just wants the same app to
  produce the same value on every rebuild, and different apps to never collide.
  """
  @spec app_guid(atom()) :: String.t()
  def app_guid(app) do
    <<a::binary-4, b::binary-2, c::binary-2, d::binary-2, e::binary-6>> =
      :crypto.hash(:md5, "rext-installer:" <> to_string(app))

    [a, b, c, d, e] |> Enum.map_join("-", &Base.encode16(&1, case: :upper))
  end

  @doc """
  Render the Inno Setup script for `app`'s cold-install path: packages
  whatever `mix rext.release` already produced (release + renderer +
  launcher) as-is, adds Start Menu / optional desktop shortcuts pointing at
  the launcher, and stops the release on uninstall so it doesn't orphan a
  running `erl.exe`.
  """
  @spec installer_iss(atom(), String.t(), String.t()) :: String.t()
  def installer_iss(app, version, publisher) do
    name = display_name(app)
    release_root_abs = release_root(app) |> Path.absname() |> String.replace("/", "\\")
    output_dir_abs = installer_output_dir() |> Path.absname() |> String.replace("/", "\\")

    """
    [Setup]
    AppId={{#{app_guid(app)}}}
    AppName=#{name}
    AppVersion=#{version}
    AppPublisher=#{publisher}
    DefaultDirName={autopf}\\#{name}
    DefaultGroupName=#{name}
    DisableProgramGroupPage=yes
    ArchitecturesAllowed=x64compatible
    ArchitecturesInstallIn64BitMode=x64compatible
    OutputDir=#{output_dir_abs}
    OutputBaseFilename=#{app}-#{version}-setup
    Compression=lzma2
    SolidCompression=yes
    UninstallDisplayIcon={app}\\bin\\run.bat

    [Files]
    Source: "#{release_root_abs}\\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

    [Tasks]
    Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

    [Icons]
    Name: "{group}\\#{name}"; Filename: "{app}\\bin\\run.bat"
    Name: "{autodesktop}\\#{name}"; Filename: "{app}\\bin\\run.bat"; Tasks: desktopicon

    [Run]
    Filename: "{app}\\bin\\run.bat"; Description: "Launch #{name} now"; Flags: nowait postinstall skipifsilent

    [UninstallRun]
    Filename: "{app}\\bin\\#{app}.bat"; Parameters: "stop"; Flags: runhidden; RunOnceId: "StopRelease"
    """
  end
end
