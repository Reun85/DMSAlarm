{
  description = "dankClock: pomodoro, timers, stopwatch and alarms for DankMaterialShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The plugin directory itself (the one containing plugin.json), which is
      # what DMS's `plugins.<name>.src` expects.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "dankClock-plugin" { } ''
          cp -r ${./dankClock} $out
          chmod +x $out/scripts/ck-sound.sh
        '';
      });

      # Logic fixtures under node; `nix flake check` runs them.
      checks = forAll (pkgs: {
        tests = pkgs.runCommand "dankClock-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
          cp -r ${./dankClock} dankClock
          cp -r ${./tests} tests
          node tests/run.mjs
          touch $out
        '';
      });

      # Registers the plugin with the DMS module the way dms-plugin-registry
      # does: `src` is filled in and `enable` defaults to false, so a user only
      # writes `programs.dank-material-shell.plugins.dankClock.enable = true`.
      homeManagerModules.default = self.homeManagerModules.dankClock;
      homeManagerModules.dankClock =
        {
          config,
          lib,
          pkgs,
          options,
          ...
        }:
        let
          plugin = {
            enable = lib.mkDefault false;
            src = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          };

          # The stable flake, the unstable flake and nixpkgs each name the
          # module differently; register under whichever one is imported.
          names = builtins.filter (n: options ? programs.${n}.plugins) [
            "dankMaterialShell"
            "dank-material-shell"
            "dms-shell"
          ];

          enabled = lib.any (n: config.programs.${n}.plugins.dankClock.enable) names;
        in
        {
          config = lib.mkMerge (
            map (n: { programs.${n}.plugins.dankClock = plugin; }) names
            ++ [
              # pw-play, used by scripts/ck-sound.sh. The default sounds are
              # bundled with the plugin.
              { home.packages = lib.mkIf enabled [ pkgs.pipewire ]; }
            ]
          );
        };
    };
}
