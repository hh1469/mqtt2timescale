{
  description = "Stores events from MQTT in postgres database";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    { self
    , nixpkgs
    , ...
    }@inputs:
    inputs.flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          formatter = inputs.treefmt-nix.lib.mkWrapper nixpkgs.legacyPackages.${system} {
            projectRootFile = "flake.nix";
            programs = {
              nixpkgs-fmt.enable = true;
            };
          };
          packages = rec {
            mqtt2timescale = pkgs.rustPlatform.buildRustPackage rec {
              pname = "mqtt2timescale";
              version = "0.2.0";

              src = ./.;
              cargoLock = {
                lockFile = ./Cargo.lock;
              };

              doCheck = true;

              env = { };
            };

            default = mqtt2timescale;
          };
          apps = rec {
            ip = inputs.flake-utils.lib.mkApp {
              drv = self.packages.${system}.mqtt2timescale;
              exePath = "/bin/mqtt2timescale";
            };
            default = ip;
          };
          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              cargo-edit
              mqttui
              rustc
              cargo
            ];
            shellHook = ''
              test -f ./env.sh && . ./env.sh
            '';
          };
        }
      )
    // {
      nixosModules.mqtt2timescale =
        { config
        , pkgs
        , lib
        , ...
        }:
          with lib;
          {
            options.services.mqtt2timescale = {
              enable = mkEnableOption "enable mqtt2timescale";
            };

            environmentFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''EnvironmentFile to define variables for mqtt2timescale '';
            };

            config = mkIf config.services.mqtt2timescale.enable {
              systemd.services.mqtt2timescale = {
                description = "Sends data from mqtt to timescale db";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];

                serviceConfig = {
                  ExecStart = "${self.packages."${pkgs.system}".mqtt2timescale}/bin/mqtt2timescale";
                  DynamicUser = true;
                  Restart = "always";
                  RestartSec = 5;
                }
                // optionalAttrs (cfg.environmentFile != null) {
                  EnvironmentFile = cfg.environmentFile;
                };
              };
            };
          };
    };
}
