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

  test "run_bat/0 shells out to the PowerShell launcher, bypassing execution policy" do
    assert Release.run_bat() =~ "-ExecutionPolicy Bypass"
    assert Release.run_bat() =~ "launcher.ps1"
  end
end
