{
  description = "Development environment for rpl";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.devshell.url = "github:numtide/devshell";
  inputs.flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";

  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "i686-linux"
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      imports = [inputs.devshell.flakeModule];
      perSystem = {
        pkgs,
        config,
        ...
      }: {
        packages = {
          rpl = pkgs.callPackage ./package.nix {inherit pkgs;};
          default = config.packages.rpl;
        };
        apps = {
          rpl = {
            type = "app";
            program = "${config.packages.rpl}/bin/rpl";
          };
          default = config.apps.rpl;
        };
        devshells.default = {
          packages = with pkgs; [
            # Development tools (only needed for development)
            alejandra
            # All Perl dependencies (runtime, test, and dev tools)
            (perl.withPackages (p:
              with p; [
                # Runtime dependencies (needed for rpl script)
                GetoptLong
                TextUnidecode
                UnicodeNormalize
                # Test dependencies (needed for rpl.t)
                TestException
                TestMore
                # Development tools (only needed for development)
                PerlCritic
                PerlTidy
              ]))
          ];
        };
      };
    };
}
