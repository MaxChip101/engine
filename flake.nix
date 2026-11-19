{
  description = "engine dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      runtimeLibs = with pkgs; [
        wayland
        libxkbcommon
        libdecor
        libGL
        libx11
        libxcursor
        libxext
        libxfixes
        libxi
        libxrandr
        libxscrnsaver
        alsa-lib
        pulseaudio
        udev
        vulkan-loader
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages =
          with pkgs;
          [
            zig_0_16
            pkg-config
            wayland-scanner
            wayland-protocols
            gdb
          ]
          ++ runtimeLibs;

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs + ":/run/opengl-driver/lib";
      };
    };
}
