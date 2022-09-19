{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, rust-overlay, ... }:
    let
      supportedSystems = [
        flake-utils.lib.system.aarch64-darwin
      ];
    in
      flake-utils.lib.eachSystem supportedSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (import rust-overlay)
            ];
          };

          rustWithWasmTarget = pkgs.rust-bin.nightly."2022-06-01".default.override {
            targets = [ "wasm32-unknown-unknown" ];
          };

          # NB: we don't need to overlay our custom toolchain for the *entire*
          # pkgs (which would require rebuidling anything else which uses rust).
          # Instead, we just want to update the scope that crane will use by appending
          # our specific toolchain there.
          craneLib = (crane.mkLib pkgs).overrideToolchain rustWithWasmTarget;

          stdenv = pkgs.llvmPackages_14.stdenv;

          rusqlite-wasm32-unknown-unknown-nix = craneLib.buildPackage ({
            inherit stdenv;
            src = ./.;
            cargoExtraArgs = "--package rusqlite-wasm32-unknown-unknown-nix";
            # crane tries to run the Wasm file as if it were a binary
            doCheck = false;
            CC = "${stdenv.cc.nativePrefix}cc";
            AR = "${stdenv.cc.nativePrefix}ar";
          });
        in
          {
            checks = {
              inherit rusqlite-wasm32-unknown-unknown-nix;
            };

            packages = {
              inherit rusqlite-wasm32-unknown-unknown-nix;
            };

            defaultPackage = rusqlite-wasm32-unknown-unknown-nix;

            devShell = pkgs.mkShell {
              # For Emacs integration
              RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;

              CC = "${stdenv.cc.nativePrefix}cc";
              AR = "${stdenv.cc.nativePrefix}ar";

              inputsFrom = builtins.attrValues self.checks;

              nativeBuildInputs = with pkgs; [
                rustWithWasmTarget
              ];
            };
          }
      );
}
