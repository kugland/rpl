# rpl

**rpl** is a powerful command-line tool for renaming files using Perl
expressions. It provides fine-grained control over batch file renaming
operations, including optional character set conversions, directory handling,
collision detection, and more.

## Features

- **Perl Expression Power**: Use Perl regular expressions and code to transform
  filenames.
- **Multiple Expressions**: Chain multiple expressions together for complex
  transformations.
- **Prebaked Expressions**: Quick access to common transformations (Unicode
  normalization, diacritic removal, whitespace trimming, &c).
- **Utility Functions**: Opt-in helper functions callable from your
  expressions, including every prebaked expression (see `--list-utils`).
- **Character Set Conversion**: Convert filenames between different character
  encodings (e.g., latin1, utf-16le, utf-8).
- **Collision Detection**: Automatically detects and handles filename
  collisions to prevent data loss.
- **Flexible Input**: Read file lists from stdin, files, or command-line
  arguments.
- **Directory Handling**: Optionally create directories as needed with
  `--mkdirp`.
- **Safe by Default**: Collision checking enabled by default; requires explicit
  `--apply` to perform renames.

## Installation

### Generic

```console
# 1. Clone or download the repository:
git clone <repository-url>
cd rpl
# 2. Make the script executable:
chmod +x rpl

# 3. Install to your system (choose one):
# System-wide installation
sudo cp rpl /usr/local/bin/

# Or add to your local bin directory
mkdir -p ~/.local/bin
cp rpl ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"  # Add to your ~/.bashrc or ~/.zshrc

# 4. (Optional) Install Perl modules if you plan to use certain features:
# Using cpanm
cpanm Unicode::Normalize Text::Unidecode

# Or using your system package manager...
```

### Arch Linux

Build and install from the included PKGBUILD:

```console
# Clone the repository
git clone https://github.com/kugland/rpl.git
cd rpl

# Build the package (and install the required Perl dependencies)
makepkg -si

# Then install the built package
sudo pacman -U rpl-3.2.3-1-any.pkg.tar.zst
```

### Nix with Flakes

#### With `nix run`

Run directly via `nix run`:

```console
nix run github:kugland/rpl
```

On your `flake.nix`:

```nix
{
  inputs = {
    […]
    rpl.url = "github:kugland/rpl";
    rpl.inputs.nixpkgs.follows = "nixpkgs";
  };

  […]
}
```

#### NixOS system configuration

Add somewhere in your NixOS configuration:

```nix
{ inputs, ... }: {
    environment.systemPackages = [ inputs.rpl.packages.${pkgs.system}.default ];
}
```

#### Home Manager

Add somewhere in your Home Manager configuration:

```nix
{ inputs, ... }: {
  home.packages = [ inputs.rpl.packages.${pkgs.system}.default ];
}
```

### Nix without Flakes

#### NixOS system configuration

Add to your `configuration.nix`:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [
    (pkgs.callPackage (builtins.fetchGit {
      url = "https://github.com/kugland/rpl";
      ref = "master";
    } + "/package.nix") {})
  ];
}
```

#### Home Manager

Add to your `home.nix`:

```nix
{ pkgs, ... }: {
  home.packages = [
    (pkgs.callPackage (builtins.fetchGit {
      url = "https://github.com/kugland/rpl";
      ref = "master";
    }) {})
  ];
}
```

## Usage

```rpl [OPTIONS] [FILES...]```

### Options

*Expression Options*

- `-e`, `--expr=EXPR`: Perl expression to apply (can be used multiple times).
- `-s`, `--script=FILE`: Read Perl expressions from a file (`-` for stdin).
- `-p`, `--prebaked=NAME`: Use a prebaked expression (see `--list-prebaked`).
- `-u`, `--util=[AS=]NAME`: Make a utility function visible to the expressions,
  optionally under the name `AS` (can be used multiple times and comma-separated;
  see `--list-utils`).

*File Input Options*

- `-f`, `--from-file=FILE`: Read list of files to rename from FILE (`-` for
  stdin).
- `-d`, `--delim=CHAR`: Set delimiter for `--from-file` (default: newline).
- `-0`, `--null`: Use NUL as delimiter for `--from-file` (useful with
  `find -print0`)

*Character Set Options*
- `-c`, `--from-charset=ENC`: Decode filenames from charset (e.g., `latin1`,
  `utf-16le`)
- `-t`, `--to-charset=ENC`: Encode filenames to charset (e.g., `latin1`,
  `utf-16le`).

*Transformation Options*

- `-b`, `--basename`: Transform only the basename (exclude directory part).
- `-x`, `--exclude-ext`: Keep original file extension unchanged.

*Behavior Options*

- `-a`, `--apply`: Actually perform renames (default is dry-run).
- `-o`, `--overwrite`: Overwrite existing files.
- `-C`, `--check-collisions`: Check for collisions (default: on).
- `-m`, `--mkdirp`: Create directories as needed.
- `-v`, `--verbose`: Be more verbose (can be used multiple times).
- `-q`, `--quiet`: Be less verbose (can be used multiple times).

*Information Options*

- `-h`, `--help`: Show help message.
- `-V`, `--version`: Show version information.
- `-l`, `--list-prebaked`: List available prebaked expressions.
- `--list-utils`: List available utility functions.

### Examples

```console
# Change `.txt` files to `.md` (dry-run by default):
rpl -e 's/\.txt$/.md/' *.txt

# To actually perform the rename:
rpl -e 's/\.txt$/.md/' -a *.txt

# Flip artist and song title in MP3 filenames:
rpl -e 's/^(.+?) - (.+?)\.mp3$/$2 - $1.mp3/' *.mp3

# Remove diacritics from all files in a directory:
find . -type f -print0 | rpl -0f- --prebaked=strip-diacritics

# Convert all filenames to lowercase:
rpl -e '$_ = lc' *

# Add a prefix to all files:
rpl -e 's/^/backup_/' *

# Add a suffix before extension:
rpl -e 's/\.([^.]+)$/_old.$1/' *

# Chain multiple expressions:
rpl -e 's/ /_/g' -e '$_ = lc' *

# Convert filenames from latin1 to utf-8:
rpl -c latin1 -t utf-8 -a *

# Transform only the filename, keeping the directory structure:
rpl -b -e '$_ = lc' *

# Transform filename but keep the original extension:
rpl -x -e 's/[^a-zA-Z0-9]/_/g' *
```

### Prebaked Expressions

Prebaked expressions provide quick access to common transformations. These
are the available prebaked expressions (you can also list them by running
`rpl --list-prebaked`):

- `collapse-blanks`: Collapse consecutive blanks, trim leading/trailing
  blanks.
- `normalize-nfc`: Normalize Unicode to canonical composition (NFC).
- `normalize-nfd`: Normalize Unicode to canonical decomposition (NFD).
- `normalize-nfkc`: Normalize Unicode to compatibility composition (NFKC).
- `normalize-nfkd`: Normalize Unicode to compatibility decomposition (NFKD).
- `strip-diacritics`: Remove diacritics from names.
- `trim`: Trim leading/trailing whitespace.
- `unidecode`: Convert Unicode characters to ASCII using `Text::Unidecode`.
- `windows-fullwidth`: Replace Windows-forbidden characters (`"`, `*`, `:`,
  `<`, `>`, `?`, `\`, `|`) with [full-width](https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)) equivalents.
- `windows-fullwidth-rev`: Reverse [full-width](https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)) replacements for
  Windows-forbidden characters.
- `windows-fullwidth-with-slash`: Like `windows-fullwidth`, but also replaces
  the Unix-forbidden `/` with its [full-width](https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)) equivalent.
- `windows-fullwidth-with-slash-rev`: Reverse [full-width](https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)) replacements for
  Windows- and Unix-forbidden characters (incl. `/`).

> [!NOTE]
> Prebaked expressions are applied in the order they are given, and can be
> combined with other expressions or character set conversions. In fact,
> a prebaked expression is just a shortcut for a specific expression or
> set of expressions.

### Utility Functions

Utility functions are helpers you can call from your expressions: building
blocks for a transformation of your own, rather than transformations of the
whole name. Each one must be requested explicitly with `--util` / `-u`, and
only the ones you request are made visible to the expressions; the rest never
enter the namespace.

These are the available utility functions (you can also list them by running
`rpl --list-utils`):

- `to_roman($n)`: Convert an integer between 1 and 3999 to a Roman numeral.
- `from_roman($s)`: Convert a Roman numeral between `I` and `MMMCMXCIX` to an
  integer. Case is ignored, but the spelling is not: only the canonical form
  `to_roman` produces is accepted, so `IIII` and `IM` are errors rather than
  `4` and `999`.

```console
# Turn chapter numbers into Roman numerals:
rpl -u to_roman -e 's/(\d+)/to_roman($1)/e' *.txt
# `chapter 19.txt' -> `chapter XIX.txt'

# And back again:
rpl -u from_roman -e 's/([IVXLCDM]+)/from_roman($1)/e' *.txt
# `chapter XIX.txt' -> `chapter 19.txt'

# Several functions at once (repeat -u, or separate names with commas):
rpl -u to_roman,from_roman -e '...' *
```

Every prebaked expression is a utility function as well, named after it with
underscores in place of hyphens: `strip-diacritics` is `strip_diacritics($s)`.
Where `--prebaked` transforms the whole name, the function transforms only
what you hand it:

```console
# Strip diacritics from the artist, and leave the title as it is:
rpl -u strip_diacritics -e 's/\A(.+?) - /strip_diacritics($1) . " - "/e' *.mp3
# `Céline Dion - Pour que tu m'aimes encore.mp3'
#   -> `Celine Dion - Pour que tu m'aimes encore.mp3'
```

A utility can be made visible under a name of your own with `AS=NAME`, which
is worth doing when a name is long and the expression calls it more than once.
Only the name you choose enters the namespace; the original does not:

```console
# Give the longer names something shorter to answer to:
rpl -u cw=collapse_blanks,sd=strip_diacritics,r=to_roman \
    -e 's/\A(.+?) - (\d+) - /cw(sd($1)) . " - " . r($2) . " - "/e' *.mp3
# `Céline  Dion - 19 - Song.mp3' -> `Celine Dion - XIX - Song.mp3'
```

> [!NOTE]
> A name must be a Perl identifier, and it can stand for only one utility:
> `-u r=to_roman -u r=trim` aborts before any name is computed. The right-hand
> side is always a name from `--list-utils` — `-u x=r=to_roman` does not chain.

> [!NOTE]
> Note the `/e` flag on the substitution above: without it, Perl treats the
> replacement as a literal string rather than code to evaluate.

> [!NOTE]
> A utility function given input it cannot handle aborts the run with an error
> naming the offending file. `to_roman` does this for `0`, negative
> numbers, non-integers, and anything above `3999`:
>
> ```console
> $ rpl -au to_roman -e 's/(\d+)/to_roman($1)/e' *.txt
> Expression 's/(\d+)/to_roman($1)/e' failed on 'ch 0.txt':
> to_roman: `0' is not an integer between 1 and 3999
> ```
>
> All new names are computed before any file is renamed, so an abort leaves
> every file untouched — no batch is ever left half-renamed.

### Character Set Conversion

**rpl** supports converting filenames between different character encodings.
To use character set conversion, you can use `--from-charset=ENC` or `-c ENC`
and `--to-charset=ENC` or `-t ENC`. The default charset is always `UTF-8`.

```console
# Convert from latin1 to utf-8
rpl -c latin1 -t utf-8 -a *

# Convert from utf-16le to utf-8
rpl -c utf-16le -t utf-8 -a *
```

> [!NOTE]
> Charset decoding is always the first step before any other transformation,
> and charset encoding is the last step after any other transformation,
> irrespective of the order of the parameters.

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests,
or pull requests.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for
details.
