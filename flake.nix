{
  description = "jekyll development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShells.default = pkgs.mkShell {
          name = "jekyll-shell";

          # Core packages for Jekyll development
          buildInputs = with pkgs; [
            talosctl
          ];

          # Optional: automatically install gems when entering the shell
          # (if a Gemfile exists)
          shellHook = ''
            if [ -f Gemfile ]; then
              echo "Gemfile found, running bundle install..."
              bundle install
            fi
          '';
        };
      }
    );
}