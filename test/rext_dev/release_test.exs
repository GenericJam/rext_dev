defmodule RextDev.ReleaseTest do
  use ExUnit.Case, async: true

  alias RextDev.Release

  test "release_root/1 is under _build/prod/rel" do
    assert Release.release_root(:my_app) == "_build/prod/rel/my_app"
  end

  test "renderer_dir/1 is inside the release root" do
    assert Release.renderer_dir(:my_app) == "_build/prod/rel/my_app/renderer"
  end

  test "renderer_source/1 points at native/windows inside the rext dep" do
    assert Release.renderer_source(%{rext: "/x/deps/rext"}) == "/x/deps/rext/native/windows"
  end

  describe "launcher_ps1/2" do
    test "pins the bridge port and passes the window id through" do
      script = Release.launcher_ps1(:my_app, "main")

      assert script =~ ~s(REXT_PORT = "#{Release.bridge_port()}")
      assert script =~ ~s(REXT_WINDOW = "main")
      assert script =~ "bin\\my_app.bat"
      assert script =~ "renderer\\rext_renderer.exe"
      assert script =~ ~s(bin\\my_app.bat" stop)
    end
  end

  describe "clean_stray_artifacts!/1" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "rext_release_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(dir, "bin"))
      File.mkdir_p!(Path.join(dir, "lib"))
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "removes launcher/BEAM runtime artifacts a prior local run left behind", %{dir: dir} do
      File.write!(Path.join(dir, "release.out.log"), "stdout")
      File.write!(Path.join(dir, "release.err.log"), "stderr")
      File.write!(Path.join(dir, "bin/erl_crash.dump"), "crash")
      File.write!(Path.join(dir, "lib/keep_me.beam"), "not a stray artifact")

      assert :ok = Release.clean_stray_artifacts!(dir)

      refute File.exists?(Path.join(dir, "release.out.log"))
      refute File.exists?(Path.join(dir, "release.err.log"))
      refute File.exists?(Path.join(dir, "bin/erl_crash.dump"))
      assert File.exists?(Path.join(dir, "lib/keep_me.beam"))
    end

    test "is a no-op when nothing stray is present", %{dir: dir} do
      assert :ok = Release.clean_stray_artifacts!(dir)
    end
  end

  test "run_bat/0 shells out to the PowerShell launcher, bypassing execution policy" do
    assert Release.run_bat() =~ "-ExecutionPolicy Bypass"
    assert Release.run_bat() =~ "launcher.ps1"
  end

  test "installer_output_dir/0 is a sibling of rel/, not inside any app's release root" do
    dir = Release.installer_output_dir()
    refute String.contains?(dir, "rel")
    assert dir == "_build/prod/installer"
  end

  describe "display_name/1" do
    test "humanizes an underscored app atom" do
      assert Release.display_name(:rext_demo) == "Rext Demo"
      assert Release.display_name(:my_app) == "My App"
    end
  end

  describe "app_guid/1" do
    test "is GUID-shaped (8-4-4-4-12 hex)" do
      assert Release.app_guid(:my_app) =~
               ~r/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/
    end

    test "is stable across calls for the same app (Inno's upgrade-detection depends on this)" do
      assert Release.app_guid(:my_app) == Release.app_guid(:my_app)
    end

    test "differs between apps" do
      refute Release.app_guid(:my_app) == Release.app_guid(:other_app)
    end
  end

  describe "installer_iss/3" do
    test "wires app metadata, the release as the file source, and the safe uninstall order" do
      iss = Release.installer_iss(:my_app, "1.2.3", "Acme Inc")

      assert iss =~ "AppId={{#{Release.app_guid(:my_app)}}}"
      assert iss =~ "AppName=My App"
      assert iss =~ "AppVersion=1.2.3"
      assert iss =~ "AppPublisher=Acme Inc"
      assert iss =~ "OutputBaseFilename=my_app-1.2.3-setup"

      # Installs whatever mix rext.release already produced, as-is (the
      # absolute prefix is CWD-dependent; the rel/my_app suffix isn't).
      assert iss =~ "rel\\my_app\\*\"; DestDir: \"{app}\""

      # Launching goes through the launcher, not the raw release script.
      assert iss =~ ~s(Filename: "{app}\\bin\\run.bat")

      # Uninstall stops the release (by its real .bat name) before Inno removes files.
      assert iss =~ ~s(Filename: "{app}\\bin\\my_app.bat"; Parameters: "stop")
    end
  end
end
