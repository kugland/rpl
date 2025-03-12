{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  perl ? pkgs.perl,
  perlPackages ? pkgs.perlPackages,
  glibcLocales ? pkgs.glibcLocales,
}: let
  perlEnv = perl.withPackages (p: [
    p.GetoptLong
    p.TextUnidecode
    p.UnicodeNormalize
  ]);
  perlTestEnv = perl.withPackages (p: [
    p.GetoptLong
    p.TextUnidecode
    p.UnicodeNormalize
    p.TestMore
    p.TestException
    p.FileTemp
  ]);
in
  stdenv.mkDerivation rec {
    pname = "rpl";
    version = "3.1.0";
    src = lib.cleanSourceWith {
      src = ./.;
      filter = path: type: let
        baseName = baseNameOf path;
      in
        baseName == "rpl" || baseName == "rpl.t" || baseName == "README.md" || baseName == ".proverc";
    };
    buildInputs = [perlEnv];
    nativeCheckInputs = [perlTestEnv glibcLocales];
    checkPhase = ''
      runHook preCheck

      # Use the Perl environment with test dependencies
      export PATH="${perlTestEnv}/bin:$PATH"
      export PERL5LIB="${perlTestEnv}/lib/perl5/site_perl/${perl.version}:${perlTestEnv}/lib/perl5/${perl.version}"

      # Run tests using prove
      prove -v rpl.t

      runHook postCheck
    '';
    doCheck = true;
    installPhase = ''
      runHook preInstall

      # Install the script
      mkdir -p $out/bin
      install -D -m 755 rpl $out/bin/rpl

      # Substitute the shebang to use the Perl environment
      substituteInPlace $out/bin/rpl --replace-fail "#!/usr/bin/env perl" "#!${perlEnv}/bin/perl"

      # Install README.md to share/doc
      mkdir -p $out/share/doc
      install -D -m 644 README.md $out/share/doc/README.md

      runHook postInstall
    '';
    meta = with lib; {
      description = "Rename files using Perl expressions";
      homepage = "https://github.com/kugland/rpl";
      license = licenses.mit;
      maintainers = [maintainers.kugland];
      platforms = platforms.unix;
      mainProgram = "rpl";
    };
  }
