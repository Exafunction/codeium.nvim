{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }
  : let
    systems = {
      "aarch64-linux" = "linux_arm";
      "aarch64-darwin" = "macos_arm";
      "x86_64-linux" = "linux_x64";
      "x86_64-darwin" = "macos_x64";
    };
  in
    flake-utils.lib.eachSystem (builtins.attrNames systems) (
      system: let
        ls-system = systems.${system};
        versions = builtins.fromJSON (builtins.readFile ./lua/codeium/versions.json);
        pkgs = import nixpkgs {
          inherit system;
        };
      in rec {
        formatter = pkgs.alejandra;

        packages = with pkgs; {
          codeium-lsp = stdenv.mkDerivation {
            pname = "codeium-lsp";
            version = "v${versions.version}";

            src = pkgs.fetchurl {
              url = "https://github.com/Exafunction/codeium/releases/download/language-server-v${versions.version}/language_server_${ls-system}";
              sha256 = versions.hashes.${system};
            };

            sourceRoot = ".";

            phases = ["installPhase" "fixupPhase"];
            nativeBuildInputs = [
              autoPatchelfHook
              stdenv.cc.cc
            ];

            installPhase = ''
              mkdir -p $out/bin
              install -m755 $src $out/bin/codeium-lsp
            '';
          };
          vimPlugins.codeium-nvim = vimUtils.buildVimPluginFrom2Nix {
            pname = "codeium";
            version = "v${versions.version}-main";
            src = ./.;
            buildPhase = ''
              cat << EOF > lua/codeium/installation_defaults.lua
              return {
                tools = {
                  language_server = "${packages.codeium-lsp}/bin/codeium-lsp"
                };
              };
              EOF
            '';
          };
          nvimWithCodeium = neovim.override {
            configure = {
              customRC = ''
                lua require("codeium").setup()
              '';
              packages.myPlugins = {
                start = [packages.vimPlugins.codeium-nvim vimPlugins.plenary-nvim vimPlugins.nvim-cmp];
              };
            };
          };
        };

        overlays.default = self: super: {
          vimPlugins =
            super.vimPlugins
            // {
              codeium-nvim = packages.vimPlugins.codeium-nvim;
            };
        };

        apps.default = {
          type = "app";
          program = "${packages.nvimWithCodeium}/bin/nvim";
        };

        devShell = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
