{
  description = "Bubblewrap sandbox claude code environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];

      perSystem = {system, ...}: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        sandboxLib = import ./lib {inherit pkgs;};

        # Interactive profile packages
        profilePackages =
          pkgs.lib.mapAttrs' (profileName: profile: rec {
            name = "claude-sandbox-${profileName}";
            value = sandboxLib.mkSandbox (profile // {inherit name;});
          })
          sandboxLib.profiles;

        # Headless profile packages (for RALPH loops)
        headlessProfilePackages =
          pkgs.lib.mapAttrs' (profileName: profile: rec {
            name = "claude-headless-${profileName}";
            value = sandboxLib.mkHeadlessSandbox (profile // {inherit name;});
          })
          sandboxLib.profiles;

      in {
        packages =
          profilePackages
          // headlessProfilePackages
          // rec {
            # Interactive (default)
            claude-sandbox = sandboxLib.mkSandbox (sandboxLib.base // {name = "claude-sandbox";});

            # Headless for RALPH loops
            claude-headless = sandboxLib.mkHeadlessSandbox (sandboxLib.base // {name = "claude-headless";});

            default = claude-sandbox;
          };

        devShells.default = sandboxLib.mkDevShell {};
      };

      flake.lib = let
        forAllSystems = inputs.nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
      in
        forAllSystems (system: let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
          import ./lib {inherit pkgs;});
    };
}
