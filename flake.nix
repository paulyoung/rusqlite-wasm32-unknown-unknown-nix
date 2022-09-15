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

          rusqlite-wasm32-unknown-unknown-nix = craneLib.buildPackage ({
            src = ./.;
            cargoExtraArgs = "--package rusqlite-wasm32-unknown-unknown-nix";
            # crane tries to run the Wasm file as if it were a binary
            doCheck = false;
            # Without setting TARGET_CC we run into:
            #
            #   "valid target CPU values are: mvp, bleeding-edge, generic"
            #
            # https://github.com/rusqlite/rusqlite/pull/1010#issuecomment-1247333415
            TARGET_CC = "${pkgs.stdenv.cc.nativePrefix}cc";
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

              # See note above about TARGET_CC
              TARGET_CC = "${pkgs.stdenv.cc.nativePrefix}cc";

              inputsFrom = builtins.attrValues self.checks;

              nativeBuildInputs = with pkgs; [
                rustWithWasmTarget
              ];
            };
          }
      );
}
