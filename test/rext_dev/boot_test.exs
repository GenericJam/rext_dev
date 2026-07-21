defmodule RextDev.BootTest do
  use ExUnit.Case, async: true

  alias RextDev.Boot

  defmodule TwoWindowApp do
    def windows, do: [{Win1, [id: "main", title: "Counter"]}, {Win2, [id: "mirror"]}]
  end

  defmodule NoIdApp do
    def windows, do: [{Win1, []}]
  end

  describe "primary_window/1" do
    test "returns the first declared window's id" do
      assert Boot.primary_window(TwoWindowApp) == "main"
    end

    test "defaults to \"main\" when the first window has no id" do
      assert Boot.primary_window(NoIdApp) == "main"
    end
  end

  describe "app_bundle/1" do
    test "derives the .app bundle from the inner executable path" do
      bin = "/x/native/macos/RextRenderer.app/Contents/MacOS/rext_renderer"
      assert Boot.app_bundle(bin) == "/x/native/macos/RextRenderer.app"
    end
  end

  describe "open_args/4" do
    test "launches via LaunchServices with the load-bearing flags" do
      args = Boot.open_args("/x/RextRenderer.app", 8137, "main", "/tmp/r.log")

      # Runs a fresh instance and blocks until it quits (the lifecycle signal).
      assert "-n" in args
      assert "-W" in args
      # Handshake env is passed through to the launched app.
      assert "REXT_PORT=8137" in args
      assert "REXT_WINDOW=main" in args
      # stderr is captured for diagnosis.
      assert Enum.slice(args, Enum.find_index(args, &(&1 == "--stderr")), 2) ==
               ["--stderr", "/tmp/r.log"]

      # The app path must be the final argument.
      assert List.last(args) == "/x/RextRenderer.app"
    end
  end

  describe "stale?/1" do
    setup do
      root = Path.join(System.tmp_dir!(), "rext_stale_#{System.unique_integer([:positive])}")
      bin = Path.join(root, "RextRenderer.app/Contents/MacOS/rext_renderer")
      src = Path.join(root, "main.swift")
      File.mkdir_p!(Path.dirname(bin))
      File.write!(bin, "binary")
      File.write!(src, "source")
      on_exit(fn -> File.rm_rf!(root) end)
      %{bin: bin, src: src}
    end

    test "true when the source is newer than the built binary", %{bin: bin, src: src} do
      File.touch!(bin, 1_000_000_000)
      File.touch!(src, 2_000_000_000)
      assert Boot.stale?(bin)
    end

    test "false when the built binary is newer than the source", %{bin: bin, src: src} do
      File.touch!(src, 1_000_000_000)
      File.touch!(bin, 2_000_000_000)
      refute Boot.stale?(bin)
    end

    test "false (use the binary) when the source can't be found", %{bin: bin, src: src} do
      File.rm!(src)
      refute Boot.stale?(bin)
    end
  end
end
