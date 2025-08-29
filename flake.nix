{
  description = "Stores events from MQTT in postgres database";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
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
    );
}
