{
  description = "Hello rust flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    rust-overlay,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {inherit system overlays;};
      rust = pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      };
      rustPlatform = pkgs.makeRustPlatform {
        rustc = rust;
        cargo = rust;
      };
    in {
      packages = rec {
        mqtt2timescale = rustPlatform.buildRustPackage rec {
          pname = "mqtt2timescale";
          version = "0.1.0";

          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          doCheck = true;

          env = {};
        };

        default = mqtt2timescale;
      };
      apps = rec {
        ip = flake-utils.lib.mkApp {
          drv = self.packages.${system}.mqtt2timescale;
          exePath = "/bin/mqtt2timescale";
        };
        default = ip;
      };
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [rust];
        shellHook = ''
          test -e ./env.sh && . ./env.sh
        '';
      };
    });
}
