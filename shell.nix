{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "dev-environment";
  buildInputs = with pkgs; [
    alejandra
    just
    pre-commit
    (perl.withPackages (p:
      with p; [
        AppFatPacker
        DataDump
        IOPty
        ListMoreUtils
        PerlCritic
        PerlTidy
        TestException
        TestMockModule
        TestMore
        TextUnidecode
        TryTiny
        perl540Packages.PLS
        Moose
      ]))
  ];
  shellHook = ''
    echo "Development environment ready..."
  '';
}
