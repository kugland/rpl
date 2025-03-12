{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "dev-environment";
  buildInputs = with pkgs; [
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
}
