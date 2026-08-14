{
  description = "evcc - extensible EV Charge Controller";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Toolchain versions are dictated by upstream:
        #   go.mod        -> go 1.26.x
        #   package.json  -> engines.node >= 26, npm >= 10
        #   CI            -> voidzero-dev/setup-vp with node 26
        go = pkgs.go_1_26;
        nodejs = pkgs.nodejs_26;

        # The UI toolchain moved from vite/eslint/prettier to Vite Plus ("vp").
        # vp ships as the `vite-plus` devDependency, so it only exists after an
        # install - but `make install-ui` already calls `vp install`. This shim
        # breaks that bootstrap cycle: prefer the project-local binary, fall
        # back to npx for the very first install.
        vp = pkgs.writeShellScriptBin "vp" ''
          if [ -x "''${PWD}/node_modules/.bin/vp" ]; then
            exec "''${PWD}/node_modules/.bin/vp" "$@"
          fi
          # `vp` is the bin of the `vite-plus` package, so npx needs --package.
          # Pin to the version package.json asks for when we can read it.
          version=$(${nodejs}/bin/node -p \
            "require(process.argv[1]).devDependencies['vite-plus']" \
            "$PWD/package.json" 2>/dev/null || true)
          case "$version" in
            "" | undefined) spec="vite-plus" ;;
            *) spec="vite-plus@$version" ;;
          esac
          echo "vp: no local install yet, bootstrapping via npx $spec" >&2
          exec ${nodejs}/bin/npx --yes --package "$spec" -- vp "$@"
        '';

        common = [
          go
          nodejs
          vp

          pkgs.gnumake
          pkgs.git

          # make lint
          pkgs.golangci-lint

          # convenience
          pkgs.sqlite
          pkgs.curl
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "evcc-devshell";
          buildInputs = common;

          shellHook = ''
            # project-local node binaries (vp, vue-tsc, tsx, playwright, ...)
            export PATH="$PWD/node_modules/.bin:$PATH"

            echo "🚗 evcc development environment"
            echo "   Go     $(go version | awk '{print $3}')"
            echo "   Node   $(node --version)"
            echo "   npm    $(npm --version)"
            echo
            echo "   make install-ui   install UI deps (vp install)"
            echo "   make ui           build the UI into dist/"
            echo "   make build        build the evcc binary (needs dist/)"
            echo "   make test         Go testsuite"
            echo "   make lint-ui      vp fmt + vp lint + vue-tsc + i18n check"
          '';
        };

        # Go only - no UI toolchain, for quick backend work
        devShells.minimal = pkgs.mkShell {
          name = "evcc-devshell-minimal";
          buildInputs = [ go pkgs.gnumake pkgs.git ];
        };
      }
    );
}
