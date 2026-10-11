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

      homeManagerModules.default = self.homeManagerModules.dankClock;
      homeManagerModules.dankClock =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.dankClock;
        in
        {
          options.programs.dankClock = {
            enable = lib.mkEnableOption "the dankClock DankMaterialShell plugin";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "inputs.dank-clock.packages.\${system}.default";
              description = "The plugin directory to install.";
            };

            settings = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.bool
                  lib.types.int
                  lib.types.str
                ]
              );
              default = { };
              example = {
                workMin = 50;
                shortBreakMin = 10;
                soundFile = "bell";
              };
              description = ''
                Plugin settings; see dankClock/Config.js for every key and its
                default. These are defaults only: values edited in the popout
                are kept in plugin state and take precedence.
              '';
            };

            installSoundDeps = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add pw-play (pipewire) to home.packages. The default sounds are bundled with the plugin.";
            };
          };

          config = lib.mkIf cfg.enable {
            programs.dank-material-shell.plugins.dankClock = {
              enable = true;
              src = cfg.package;
              settings = cfg.settings;
            };

            home.packages = lib.mkIf cfg.installSoundDeps [ pkgs.pipewire ];
          };
        };
    };
}
