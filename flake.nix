{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = ["rust-src" "cargo" "rustc" "clippy" "llvm-tools-preview"];
        };
        nativeBuildInputs = with pkgs; [
        ];
        buildInputs = with pkgs; [
        ];
        packages = with pkgs; [
          overmind
          mitmproxy
        ];
      in {
        formatter = pkgs.alejandra;
        devShell = pkgs.mkShell {
          inherit nativeBuildInputs buildInputs packages;
        };
      }
    );
}
