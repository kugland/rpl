# rpl

**Version**: v3.0.0
**Author**: André Kugland
**License**: MIT

---

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Usage](#usage)
- [Installation](#installation)
- [Examples](#examples)
- [Prebaked Expressions](#prebaked-expressions)
- [Contributing](#contributing)
- [License](#license)

---

## Introduction

**rpl** is a command-line tool for renaming files using Perl expressions. It performs powerful batch renames with full control over every aspect of filename transformations, including optional character set conversions, directory handling, collision checks, and more.

---

## Features

- **Multiple expressions**: Chain multiple Perl `-e` expressions.
- **Prebaked expressions**: Quick access to common transformations (e.g., removing diacritics, normalizing Unicode, trimming whitespace, etc.).
- **Character set conversion**: Convert filenames from one charset to another.
- **Collision checks**: Prevent accidental overwrites by detecting (and dodging) collisions.
- **Dry-run vs. apply**: Preview changes before committing them.
- **Easy integration**: Can read from and write file lists via standard input or plain text files.
- **Extensible**: Simply add your own scripts or expressions for complete flexibility.

---

## Usage

```bash
rpl [OPTIONS] [FILES...]

Where [OPTIONS] can include (but are not limited to):

    -e, --expr=EXPR
    Perl expression to apply (can be used multiple times).

    -s, --script=FILE
    Read Perl expressions from a file (- for stdin).

    -p, --prebaked=NAME
    Use a prebaked expression (see --list-prebaked).

    -f, --from-file=FILE
    Read list of files to rename from FILE (- for stdin).

    -d, --delim=CHAR
    Set delimiter for --from-file (default: newline).

    -0, --null
    Use NUL as the delimiter for --from-file.

    -c, --from-charset=ENC
    Decode filenames from charset (e.g. latin1, utf-16le).

    -t, --to-charset=ENC
    Encode filenames to charset (e.g. latin1, utf-16le).

    -b, --basename
    Exclude directory part of the filename.

    -x, --exclude-ext
    Keep the original file extension unchanged.

    -o, --overwrite
    Overwrite existing files.

    -C, --check-collisions
    Check for collisions (default is on).

    -a, --apply
    Actually perform renames (default is dry-run).

    -m, --mkdirp
    Create directories as needed.

    -v, --verbose
    Be more verbose (can be used multiple times).

    -q, --quiet
    Be less verbose (can be used multiple times).

    -h, --help
    Show help message.

    -V, --version
    Show version information.

    -l, --list-prebaked
    List available prebaked expressions.

Boolean options (e.g., --basename, --exclude-ext) can be negated by prefixing with no- (e.g., --no-apply).
Installation

    Clone or download the repository.
    Ensure that Perl (v5.36 or newer recommended) is installed on your system.
    Make the script executable:

chmod +x rpl

Place rpl somewhere in your $PATH, for instance:

    sudo cp rpl /usr/local/bin/

    (Optional) Install any additional Perl modules mentioned in the script if you plan to use certain features (e.g., Unicode::Normalize, Text::Unidecode).

Examples

    Convert .txt files to .md (dry-run by default):

rpl -e 's/\.txt$/.md/' *.txt

To actually perform the rename, add --apply (or -a):

rpl -e 's/\.txt$/.md/' -a *.txt

Rearrange filenames containing a pattern
Suppose you have MP3 files named in the format Artist - Song.mp3 and want to flip them:

rpl -e 's/^(.+?) - (.+?)\.mp3$/$2 - $1.mp3/' *.mp3

Again, use --apply to finalize.

Remove diacritics
If you have a list of filenames piped from find:

    find . -type f -print0 | rpl -0f- --prebaked=strip-diacritics

    Once more, include --apply to actually rename the files.

Prebaked Expressions

Run:

rpl --list-prebaked

You will see a list of predefined expressions such as:

    strip-diacritics
    trim
    normalize-nfc
    collapse-blanks
    etc.

They can be combined with other expressions in a single command.
Contributing

    Fork the repository.
    Create your feature branch:

git checkout -b feature/my-awesome-feature

Commit your changes:

git commit -am 'Add my awesome feature'

Push to the branch:

    git push origin feature/my-awesome-feature

    Create a new Pull Request.

License

This project is licensed under the MIT License. See LICENSE for details.
