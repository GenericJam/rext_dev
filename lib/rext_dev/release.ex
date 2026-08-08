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
end
