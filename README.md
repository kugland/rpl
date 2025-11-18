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

# Or using your system package manager
# Debian/Ubuntu:
sudo apt-get install libunicode-normalize-perl libtext-unidecode-perl
# Arch Linux:
sudo pacman -S perl-unicode-normalize perl-text-unidecode
# For other distros, check how to installed these packages.
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
sudo pacman -U rpl-3.1.0-1-any.pkg.tar.zst
```

#### Nix with Flakes

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

**NixOS system configuration:**

Add somewhere in your NixOS configuration:

```nix
{ inputs, ... }: {
    environment.systemPackages = [ inputs.rpl.packages.${pkgs.system}.default ];
}
```

**Home Manager:**

Add somewhere in your Home Manager configuration:

```nix
{ inputs, ... }: {
  home.packages = [ inputs.rpl.packages.${pkgs.system}.default ];
}
```

#### Nix without Flakes

**NixOS system configuration:**

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

**Home Manager:**

Add to your `home.nix`:

```nix
{ pkgs, ... }: {
  home.packages = [
    (pkgs.callPackage (builtins.fetchGit {
      url = "https://github.com/kugland/rpl";
      ref = "master";
    } + "/package.nix") {})
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

## Examples

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

## Prebaked Expressions

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
  Windows-forbidden characters

> [!NOTE]
> Prebaked expressions are applied in the order they are given, and can be
> combined with other expressions or character set conversions. In fact,
> a prebaked expression is just a shortcut for a specific expression or
> set of expressions.

## Character Set Conversion

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
