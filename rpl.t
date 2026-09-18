## no critic (Modules::ProhibitExcessMainComplexity, Modules::RequireExplicitPackage)
use 5.036;
use strict;
use warnings;
use utf8;
use autodie;

use English '-no_match_vars';
use Test::More;
use Test::Exception;
use File::Temp qw{tempfile tempdir};
use Encode;
use Cwd;

require './rpl'; ## no critic (RequireBarewordIncludes)


sub capture_sub_output {
  my ($sub) = @_;
  pipe my $out_reader, my $out_writer or die;
  pipe my $err_reader, my $err_writer or die;
  if ( ( my $pid = fork() ) == 0 ) {
    close $out_reader;
    close $err_reader;
    open STDOUT, '>&', fileno($out_writer) or die;
    open STDERR, '>&', fileno($err_writer) or die;
    $sub->();
    exit 0;
  } else {
    close $out_writer;
    close $err_writer;
    my $stdout = do { local $RS = undef; <$out_reader> };
    my $stderr = do { local $RS = undef; <$err_reader> };
    close $out_reader;
    close $err_reader;
    waitpid( $pid, 0 ); ## no critic (RequireCheckedSyscalls)
    return ( $CHILD_ERROR >> 8, $stdout, $stderr );
  } ## end else [ if ( ( my $pid = fork(...)))]
} ## end sub capture_sub_output


# Absolute path to the script under test, captured before any test chdir()s away.
my $RPL_SCRIPT = getcwd() . '/rpl';


# Run ./rpl as a real subprocess and return its true exit code.
# capture_sub_output() cannot observe exit codes: it calls main() as a function
# and then exits 0 under its own steam, so the script's own `exit' line never
# runs. Only a subprocess exercises the real exit path.
sub run_script {
  my ( $opts, @args ) = @_;
  pipe my $out_reader, my $out_writer or die;
  pipe my $err_reader, my $err_writer or die;
  my $pid = fork();
  defined $pid or die;
  if ( $pid == 0 ) {
    close $out_reader;
    close $err_reader;
    open STDOUT, '>&', fileno($out_writer) or die;
    open STDERR, '>&', fileno($err_writer) or die;
    if ( defined $opts->{cwd} ) { chdir $opts->{cwd} or die }
    exec $EXECUTABLE_NAME, $RPL_SCRIPT, @args or exit 127;
  } ## end if ( $pid == 0 )
  close $out_writer;
  close $err_writer;
  my $stdout = do { local $RS = undef; <$out_reader> };
  my $stderr = do { local $RS = undef; <$err_reader> };
  close $out_reader;
  close $err_reader;
  waitpid( $pid, 0 ); ## no critic (RequireCheckedSyscalls)
  return ( $CHILD_ERROR >> 8, $stdout, $stderr );
} ## end sub run_script


sub create_tempfile {
  my ( $content, $delim ) = @_;
  $delim //= "\n";
  my ( $fh, $filename ) = tempfile( UNLINK => 1 );
  print {$fh} join( $delim, @{$content} ) if @{$content};
  close $fh;
  return "$filename";
} ## end sub create_tempfile


sub create_file {
  my ( $filename, $content ) = @_;
  open my $fh, '>', $filename;
  print {$fh} $content if defined $content;
  close $fh;
  return "$filename";
} ## end sub create_file


sub assert_file_content {
  my ( $filename, $content ) = @_;
  ok -e $filename, "$filename exists";
  my $actual = do {
    local $RS = undef;
    open my $f, '<', $filename;
    my $data = <$f>;
    close $f;
    $data;
  };
  is $actual, $content, "$filename content matches";
  return;
} ## end sub assert_file_content


subtest 'params_get' => sub {
  # Expression handling
  subtest 'Expression sources' => sub {
    my $p = params_get(qw{ -e tr/ab/ba/ -e s/a/b/ a });
    is scalar @{ $p->{exprs} },       2,           '2 exprs';
    is $p->{exprs}[0]{expr},          'tr/ab/ba/', 'First expr';
    is $p->{exprs}[1]{expr},          's/a/b/',    'Second expr';
    is $p->{exprs}[0]{func}->('abc'), 'bac',       'First expr works';
    is $p->{exprs}[1]{func}->('abc'), 'bbc',       'Second expr works';
    my $script = create_tempfile( ['tr/A-Z/a-z/; s/ //g'] );
    $p = params_get( "-s$script", 'a' );
    is scalar @{ $p->{exprs} },         1,                     '1 exprs from script';
    is $p->{exprs}[0]{expr},            'tr/A-Z/a-z/; s/ //g', 'Expr from script';
    is $p->{exprs}[0]{func}->('A B C'), 'abc',                 'Expr from script works';
    open STDIN, '<', create_tempfile( ['tr/a-z/A-Z/; s/ /_/g'], "\0" );
    $p = params_get( '-s-', 'a' );
    is scalar @{ $p->{exprs} },         1,                      '1 exprs from stdin';
    is $p->{exprs}[0]{expr},            'tr/a-z/A-Z/; s/ /_/g', 'Expr from stdin';
    is $p->{exprs}[0]{func}->('a b c'), 'A_B_C',                'Expr from stdin works';
    $p = params_get(qw{ --prebaked=collapse-blanks a });
    is scalar @{ $p->{exprs} },                 1,       '1 exprs from prebaked';
    is $p->{exprs}[0]{func}->("  a\t b \n c "), 'a b c', 'Prebaked expr works';
  }; ## end 'Expression sources' => sub
  # File input handling
  subtest 'File sources' => sub {
    my $p = params_get(qw{ -e1 a b c });
    is_deeply $p->{files}, [qw{ a b c }], 'Files from command line';
    my $input = create_tempfile( [qw{ file1.txt file2.jpg }], q{:} );
    $p = params_get( '-e1', '--delim=:', "--from-file=$input" );
    is_deeply $p->{files}, [qw{ file1.txt file2.jpg }], 'Files from file';
    open STDIN, '<', create_tempfile( [qw{ file3.txt file4.jpg }], "\0" );
    $p = params_get( '-e1', "--delim=\0", '-f-' );
    is_deeply $p->{files}, [qw{ file3.txt file4.jpg }], 'Files from stdin';
    $p = params_get(qw{ -e1 a b a b });
    is_deeply $p->{files}, [qw{ a b }], 'Unique files only';
  }; ## end 'File sources' => sub
  # Character encoding
  subtest 'Character encoding' => sub {
    for my $dir (qw{ from to }) {
      subtest "--$dir-charset" => sub {
        my $p = params_get( '-e1', 'a', "--$dir-charset=latin1" );
        is $p->{"${dir}_charset"}{name}, 'latin1', 'Valid charset set';
        isa_ok $p->{"${dir}_charset"}{codec}, 'Encode::Encoding', 'Codec initialized';
        my $counter = 0;
        $counter += $p->{"${dir}_charset"}{codec}->decode( chr $_ ) eq ( chr $_ ) for 0 .. 255;
        is $counter, 256, 'Codec is really latin1';
      } ## end sub
    } ## end for my $dir (qw{ from to })
  }; ## end 'Character encoding' => sub
  # Boolean options
  subtest 'Boolean flags' => sub {
    my @opts = ( qw{
        -b  --basename     --no-basename     basename
        -x  --exclude-ext  --no-exclude-ext  exclude_ext
        -a  --apply        --no-apply        apply
        -m  --mkdirp       --no-mkdirp       mkdirp
        -o  --overwrite    --no-overwrite    overwrite
    } );
    for my ( $long, $short, $negate, $key ) (@opts) {
      subtest "$short, $long, $negate" => sub {
        my $p = params_get(qw{-e1 a});
        is $p->{$key}, 0, 'Default is false';
        $p = params_get( qw{-e1 a}, $short );
        is $p->{$key}, 1, 'Short flag works';
        $p = params_get( qw{-e1 a}, $long );
        is $p->{$key}, 1, 'Long flag works';
        $p = params_get( qw{-e1 a}, $negate );
        is $p->{$key}, 0, 'Negated flag works';
      } ## end sub
    } ## end for my ( $long, $short,...)
  }; ## end 'Boolean flags' => sub
  # Error conditions
  subtest 'Error handling' => sub {
    ## no critic (RequireLineBoundaryMatching, RequireDotMatchAnything)
    throws_ok { params_get(qw{ a }) } qr/no expressions provided/i,              'No expressions';
    throws_ok { params_get(qw{ -e1 }) } qr/no files provided/i,                  'No files';
    throws_ok { params_get(qw{ --invalid-option }) } qr/unknown option/i,        'Unknown option';
    throws_ok { params_get(qw{ -fnot-found }) } qr/can't open file/i,            'File not found';
    throws_ok { params_get(qw{ -snot-found }) } qr/can't open file/i,            'Script not found';
    throws_ok { params_get(qw{ -e1 a -cinvalid }) } qr/unknown charset/i,        'Invalid charset';
    throws_ok { params_get(qw{ -e1 a -tinvalid }) } qr/unknown charset/i,        'Invalid charset';
    throws_ok { params_get(qw{ -e BEGIN{die} a }) } qr/compilation failed/i,     'Script error';
    throws_ok { params_get(qw{ -dab -e1 -f/dev/null }) } qr/invalid delimiter/i, 'Invalid delim';
    ## use critic
  }; ## end 'Error handling' => sub
  # Verbosity levels
  subtest 'Verbosity levels' => sub {
    subtest 'Default verbosity' => sub {
      my $p = params_get( '-e', 's/foo/bar/', 'a' );
      is $p->{verbosity}, 1, 'Default verbosity is 1';
    };
    subtest 'Verbose flag' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-v', 'a' );
      is $p->{verbosity}, 2, 'Single -v increases verbosity';
      $p = params_get( '-e', 's/foo/bar/', '-v', '-v', 'a' );
      is $p->{verbosity}, 3, 'Multiple -v increases verbosity';
    }; ## end 'Verbose flag' => sub
    subtest 'Quiet flag' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-q', 'a' );
      is $p->{verbosity}, 0, 'Single -q decreases verbosity';
      $p = params_get( '-e', 's/foo/bar/', '-q', '-q', 'a' );
      is $p->{verbosity}, 0, 'Verbosity clamped to 0';
    }; ## end 'Quiet flag' => sub
    subtest 'Verbose and quiet together' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-v', '-q', 'a' );
      is $p->{verbosity}, 1, 'Verbose and quiet cancel';
      $p = params_get( '-e', 's/foo/bar/', '-v', '-v', '-q', 'a' );
      is $p->{verbosity}, 2, 'Multiple verbose and quiet (2v - 1q = 1, but starts at 1)';
    }; ## end 'Verbose and quiet together' => sub
  }; ## end 'Verbosity levels' => sub
}; ## end 'params_get' => sub


subtest 'read_file' => sub {
  subtest 'Reads from file' => sub {
    my $file  = create_tempfile( [qw{line1 line2 line3}] );
    my @lines = read_file( $file, "\n" );
    is_deeply \@lines, [qw{line1 line2 line3}], 'Reads lines from file';
  };
  subtest 'Reads from stdin' => sub {
    open STDIN, '<', create_tempfile( [qw{stdin1 stdin2}] );
    my @lines = read_file( q{-}, "\n" );
    is_deeply \@lines, [qw{stdin1 stdin2}], 'Reads lines from stdin';
  };
  subtest 'Handles custom delimiter' => sub {
    my $file  = create_tempfile( [qw{item1 item2 item3}], q{:} );
    my @lines = read_file( $file, q{:} );
    is_deeply \@lines, [qw{item1 item2 item3}], 'Reads with custom delimiter';
  };
  subtest 'Handles null delimiter' => sub {
    my $file  = create_tempfile( [qw{null1 null2}], "\0" );
    my @lines = read_file( $file, "\0" );
    is_deeply \@lines, [qw{null1 null2}], 'Reads with null delimiter';
  };
  subtest 'Filters empty lines when delimiter set' => sub {
    my $file  = create_tempfile( [ qw{line1}, q{}, q{}, qw{line2} ], "\n" );
    my @lines = read_file( $file, "\n" );
    is_deeply \@lines, [qw{line1 line2}], 'Filters empty lines';
  };
  subtest 'Keeps empty lines when delimiter not set' => sub {
    my $file  = create_tempfile( [ qw{line1}, q{}, qw{line2} ], "\n" );
    my @lines = read_file( $file, undef );
    # When delimiter is undef, $INPUT_RECORD_SEPARATOR is undef, so whole file is read as one line
    is scalar @lines, 1, 'Reads whole file when delimiter undefined';
    like $lines[0], qr/line1.*line2/sm, 'File content preserved';
  }; ## end 'Keeps empty lines when delimiter not set' => sub
  subtest 'Error handling' => sub {
    throws_ok { read_file( 'nonexistent-file', "\n" ) } qr/can't open file/ism, 'File not found';
    throws_ok { read_file( create_tempfile( ['test'] ), 'ab' ) } qr/invalid delimiter/ism, 'Invalid delimiter length';
  };
}; ## end 'read_file' => sub


subtest 'compile_exprs' => sub {
  subtest 'Compiles single expression' => sub {
    my $exprs = compile_exprs('s/foo/bar/');
    is scalar @{$exprs},           1,            'One expression compiled';
    is $exprs->[0]{expr},          's/foo/bar/', 'Expression preserved';
    is $exprs->[0]{func}->('foo'), 'bar',        'Function works';
  }; ## end 'Compiles single expression' => sub
  subtest 'Compiles multiple expressions' => sub {
    my $exprs = compile_exprs( 's/foo/bar/', 's/bar/baz/' );
    is scalar @{$exprs},           2,     'Two expressions compiled';
    is $exprs->[0]{func}->('foo'), 'bar', 'First function works';
    is $exprs->[1]{func}->('bar'), 'baz', 'Second function works';
  }; ## end 'Compiles multiple expressions' => sub
  subtest 'Handles UTF-8 expressions' => sub {
    my $exprs = compile_exprs('s/foo/世界/');
    is $exprs->[0]{func}->('foo'), '世界', 'UTF-8 expression works';
  };
  subtest 'Error handling' => sub {
    throws_ok { compile_exprs('BEGIN{die "test"}') } qr/compilation failed/ism, 'Compilation error';
  };
}; ## end 'compile_exprs' => sub


subtest 'prebaked_get' => sub {
  subtest 'Gets known prebaked expression' => sub {
    my $expr = prebaked_get('trim');
    like $expr, qr/s\/.*\s/sm, 'Returns expression string with substitution';
    ok length $expr > 0, 'Expression is not empty';
  };
  subtest 'Error handling' => sub {
    throws_ok { prebaked_get('nonexistent') } qr/unknown prebaked expression/ism, 'Unknown expression';
  };
}; ## end 'prebaked_get' => sub


subtest 'prebaked_list' => sub {
  my ( $exit, $out, $err ) = capture_sub_output( sub { prebaked_list() } );
  is $exit, 0, 'Exits successfully';
  like $out, qr/The following prebaked expressions are available:/sm, 'Header present';
  like $out, qr/collapse-blanks/sm,                                   'Lists collapse-blanks';
  like $out, qr/trim/sm,                                              'Lists trim';
  like $out, qr/strip-diacritics/sm,                                  'Lists strip-diacritics';
  is $err, q{}, 'No stderr output';
}; ## end 'prebaked_list' => sub


subtest 'prebaked exprs' => sub {
  ## no critic (ProhibitEscapedCharacters)
  my @CASES = (
    [ 'collapse-blanks',                  " a  \t\x{2003} \n b\tc ", 'a b c' ],
    [ 'normalize-nfc',                    "Ａa\x{0301}",              q{Ａá} ],
    [ 'normalize-nfd',                    q{Ａá},                     "Ａa\x{0301}" ],
    [ 'normalize-nfkc',                   "ＡＡ\x{0301}",              'AÁ' ],
    [ 'normalize-nfkd',                   'Ａá',                      "Aa\x{0301}" ],
    [ 'strip-diacritics',                 'áéíóúý',                  'aeiouy' ],
    [ 'trim',                             "  \t\n  hello  \t\n  ",   'hello' ],
    [ 'unidecode',                        'Христос—αἰώνιον 道',       'Khristos--aionion Dao ' ],
    [ 'windows-fullwidth',                '\\/:"<>|?*',              '＼/：＂＜＞｜？＊' ],
    [ 'windows-fullwidth-rev',            '＼/：＂＜＞｜？＊',               '\\/:"<>|?*' ],
    [ 'windows-fullwidth-with-slash',     '\\/:"<>|?*',              '＼／：＂＜＞｜？＊' ],
    [ 'windows-fullwidth-with-slash-rev', '＼／：＂＜＞｜？＊',               '\\/:"<>|?*' ],
  );
  for my $case (@CASES) {
    my ( $name, $input, $output ) = @{$case};
    my $p = params_get( "--prebaked=$name", 'a' );
    is $p->{exprs}[0]{func}->($input), $output, "$name works";
  }
}; ## end 'prebaked exprs' => sub


# Parse a Roman numeral back to an integer. Test-only inverse of `to_roman`,
# used to round-trip the whole 1..3999 range. Deliberately kept independent of
# the production `from_roman`: it shares no code with it, so a round trip
# through this oracle cannot be satisfied by a bug the two functions agree on.
sub roman_to_int {
  my ($roman) = @_;
  my %value   = ( I => 1, V => 5, X => 10, L => 50, C => 100, D => 500, M => 1000 );
  my @digits  = map { $value{$_} } split //msx, $roman;
  my $total   = 0;
  for my $i ( 0 .. $#digits ) {
    $total += ( $i < $#digits && $digits[$i] < $digits[ $i + 1 ] ) ? -$digits[$i] : $digits[$i];
  }
  return $total;
} ## end sub roman_to_int


# NOTE: installing a utility mutates the expression package process-wide, so
# this subtest must stay ahead of every subtest that calls `utils_install`.
subtest 'utils absent until selected' => sub {
  ok !Isolated::Eval::Context->can('to_roman'), 'Not in expression package before selection';
  my $p = params_get( '-e', '$_', 'a' );
  ok !Isolated::Eval::Context->can('to_roman'), 'Still absent when --util is not given';
  ok !Isolated::Eval::Context->can('trim'),     'Prebaked-derived utility absent as well';
}; ## end 'utils absent until selected' => sub


subtest 'utils_get' => sub {
  subtest 'Gets known utility function' => sub {
    my $func = utils_get('to_roman');
    is ref $func, 'CODE', 'Returns a coderef';
  };
  subtest 'Error handling' => sub {
    throws_ok { utils_get('nonexistent') } qr/unknown utility function/ism, 'Unknown utility';
  };
}; ## end 'utils_get' => sub


subtest 'utils_list' => sub {
  my ( $exit, $out, $err ) = capture_sub_output( sub { utils_list() } );
  is $exit, 0, 'Exits successfully';
  like $out, qr/The following utility functions are available:/sm, 'Header present';
  like $out, qr/to_roman/sm,                                       'Lists to_roman';
  like $out, qr/from_roman/sm,                                     'Lists from_roman';
  is $err, q{}, 'No stderr output';
}; ## end 'utils_list' => sub


subtest 'to_roman' => sub {
  ## no critic (ProhibitMagicNumbers) -- the numerals below are the domain's own values.
  my $to_roman = utils_get('to_roman');
  subtest 'Converts integers in range' => sub {
    my @CASES = (
      [ 1,    'I' ],      [ 2,    'II' ], [ 3,    'III' ],  [ 4,   'IV' ],
      [ 5,    'V' ],      [ 9,    'IX' ], [ 10,   'X' ],    [ 14,  'XIV' ],
      [ 19,   'XIX' ],    [ 40,   'XL' ], [ 49,   'XLIX' ], [ 50,  'L' ],
      [ 90,   'XC' ],     [ 100,  'C' ],  [ 400,  'CD' ],   [ 500, 'D' ],
      [ 900,  'CM' ],     [ 1000, 'M' ],  [ 1987, 'MCMLXXXVII' ],
      [ 2024, 'MMXXIV' ], [ 3999, 'MMMCMXCIX' ],
    );
    for my $case (@CASES) {
      my ( $input, $output ) = @{$case};
      is $to_roman->($input), $output, "$input -> $output";
    }
  }; ## end 'Converts integers in range' => sub
  subtest 'Round-trips the whole 1..3999 range' => sub {
    my @bad = grep { roman_to_int( $to_roman->($_) ) != $_ } 1 .. 3999;
    is scalar @bad,     0,   'Every value round-trips';
    is $to_roman->($_), q{}, "Round-trip failed for $_" for @bad;
  };
  subtest 'Rejects out-of-range and non-numeric input' => sub {
    for my $bad ( 0, -1, 4000, 10_000, 'foo', q{}, '3.5', '1e3', ' 19', '19 ', '+19' ) {
      throws_ok { $to_roman->($bad) } qr/to_roman/ism, "Dies on `$bad'";
    }
  };
}; ## end 'to_roman' => sub


subtest 'from_roman' => sub {
  ## no critic (ProhibitMagicNumbers) -- the numerals below are the domain's own values.
  my $from_roman = utils_get('from_roman');
  subtest 'Converts canonical numerals in range' => sub {
    my @CASES = (
      [ 'I',      1 ],    [ 'II',        2 ],    [ 'III',        3 ],   [ 'IV',  4 ],
      [ 'V',      5 ],    [ 'IX',        9 ],    [ 'X',          10 ],  [ 'XIV', 14 ],
      [ 'XIX',    19 ],   [ 'XL',        40 ],   [ 'XLIX',       49 ],  [ 'L',   50 ],
      [ 'XC',     90 ],   [ 'C',         100 ],  [ 'CD',         400 ], [ 'D',   500 ],
      [ 'CM',     900 ],  [ 'M',         1000 ], [ 'MCMLXXXVII', 1987 ],
      [ 'MMXXIV', 2024 ], [ 'MMMCMXCIX', 3999 ],
    );
    for my $case (@CASES) {
      my ( $input, $output ) = @{$case};
      is $from_roman->($input), $output, "$input -> $output";
    }
  }; ## end 'Converts canonical numerals in range' => sub
  subtest 'Inverts to_roman across the whole 1..3999 range' => sub {
    my $to_roman = utils_get('to_roman');
    my @bad      = grep { $from_roman->( $to_roman->($_) ) != $_ } 1 .. 3999;
    is scalar @bad,                      0,  'Every value round-trips';
    is $from_roman->( $to_roman->($_) ), $_, "Round-trip failed for $_" for @bad;
  }; ## end 'Inverts to_roman across the whole 1..3999 range' => sub
  subtest 'Accepts lowercase and mixed case' => sub {
    is $from_roman->('xix'),        19,   'Lowercase xix';
    is $from_roman->('XiX'),        19,   'Mixed-case XiX';
    is $from_roman->('mcmlxxxvii'), 1987, 'Lowercase mcmlxxxvii';
    is $from_roman->('mMmCmXcIx'),  3999, 'Mixed-case mMmCmXcIx';
  }; ## end 'Accepts lowercase and mixed case' => sub
  subtest 'Rejects non-canonical numerals' => sub {
    for my $bad (qw{ IIII VV XXXX LL DD MMMM IM IC XM VX IIX XIIX VIV }) {
      throws_ok { $from_roman->($bad) } qr/from_roman/ism, "Dies on `$bad'";
    }
  };
  subtest 'Rejects empty and non-numeral input' => sub {
    for my $bad ( q{}, 'foo', '19', 'XIX ', ' XIX', 'X I X', "XIX\n", 'MCMLXXXVIIA', 'A' ) {
      throws_ok { $from_roman->($bad) } qr/from_roman/ism, "Dies on `$bad'";
    }
    throws_ok { $from_roman->(undef) } qr/from_roman/ism, 'Dies on undef';
  }; ## end 'Rejects empty and non-numeral input' => sub
}; ## end 'from_roman' => sub


subtest 'util option' => sub {
  subtest 'Installs into the expression package' => sub {
    my $p = params_get( '--util=to_roman', '-e', 's/(\d+)/to_roman($1)/e', 'a' );
    is_deeply $p->{utils}, ['to_roman'], 'Selected utility recorded';
    ok Isolated::Eval::Context->can('to_roman'), 'Installed in expression package';
    is $p->{exprs}[0]{func}->('track 19.mp3'), 'track XIX.mp3', 'Expression can call it';
  }; ## end 'Installs into the expression package' => sub
  subtest 'Installs from_roman into the expression package' => sub {
    my $p = params_get( '-u', 'to_roman,from_roman', '-e', 's/([IVXLCDM]+)/from_roman($1)/e', 'a' );
    is_deeply $p->{utils}, [ 'to_roman', 'from_roman' ], 'Both utilities recorded in order';
    ok Isolated::Eval::Context->can('from_roman'), 'Installed in expression package';
    is $p->{exprs}[0]{func}->('track XIX.mp3'), 'track 19.mp3', 'Expression can call it';
  }; ## end 'Installs from_roman into the expression package' => sub
  subtest 'Accepts short form, repetition and comma-separated lists' => sub {
    my $p = params_get( '-u', 'to_roman', '-e', '$_', 'a' );
    is_deeply $p->{utils}, ['to_roman'], 'Short form works';
    $p = params_get( '-u', 'to_roman,to_roman', '-u', 'to_roman', '-e', '$_', 'a' );
    is_deeply $p->{utils}, ['to_roman'], 'Duplicates collapse to one';
  }; ## end 'Accepts short form, repetition and comma-separated lists' => sub
  subtest 'Error handling' => sub {
    throws_ok { params_get( '-u', 'nonexistent', '-e', '$_', 'a' ) }
    qr/unknown utility function/ism, 'Unknown utility rejected';
  };
  subtest 'Errors from a utility name the file and expression' => sub {
    my $p = params_get( '--util=to_roman', '-e', 's/(\d+)/to_roman($1)/e', 'track 0.mp3' );
    throws_ok { transform_name( $p, 'track 0.mp3' ) } qr/track\ 0\.mp3/msx, 'Error names the file';
  };
}; ## end 'util option' => sub


subtest 'prebaked utility functions' => sub {
  subtest 'Applies a single-expression prebaked to its argument' => sub {
    my $func = utils_get('strip_diacritics');
    is $func->('Édition Française'), 'Edition Francaise', 'Diacritics removed from the argument';
  };
  subtest 'Applies every expression of a multi-expression prebaked' => sub {
    my $func = utils_get('collapse_blanks');
    is $func->('  a   b  '), 'a b', 'Blanks collapsed and trimmed';
  };
  subtest 'Is selected by --util like any other utility' => sub {
    my $p = params_get( '-u', 'strip_diacritics', '-e', 's/(.+)/strip_diacritics($1)/e', 'a' );
    is_deeply $p->{utils}, ['strip_diacritics'], 'Selected utility recorded';
    ok Isolated::Eval::Context->can('strip_diacritics'), 'Installed in expression package';
    is $p->{exprs}[0]{func}->('Ação'), 'Acao', 'Expression can call it';
  }; ## end 'Is selected by --util like any other utility' => sub
  subtest 'Is known only under its underscored name' => sub {
    throws_ok { utils_get('strip-diacritics') } qr/unknown utility function/ism,
      'Hyphenated name rejected';
  };
  subtest 'Treats a missing argument as the empty string' => sub {
    is utils_get('trim')->(undef), q{}, 'undef trims to the empty string';
  };
  subtest 'Names itself when its expression cannot be compiled' => sub {
    local %INC = %INC;                              # Hide the module the expression requires,
    delete $INC{'Unicode/Normalize.pm'};            # so that compiling it is bound to fail.
    local @INC = ();
    throws_ok { utils_get('normalize_nfkd') } qr/normalize_nfkd/ms,    'Error names the utility';
    throws_ok { utils_get('normalize_nfkd') } qr/Unicode.Normalize/ms, 'Error names the cause';
    unlike $EVAL_ERROR, qr/compilation\ failed\ for\ expr/imsx, 'Without the expression preamble';
  }; ## end 'Names itself when its expression cannot be compiled' => sub
  subtest 'Is listed beside the hand-written utilities' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { utils_list() } );
    is $exit, 0, 'Exits successfully';
    like $out, qr/strip_diacritics\(\$s\)/sm,          'Lists the derived signature';
    like $out, qr/Remove\ diacritics\ from\ names/msx, 'Reuses the prebaked description';
    like $out, qr/to_roman/sm,                         'Hand-written utilities still listed';
    is utils_get('to_roman'), \&to_roman, 'Hand-written utilities not overwritten';
    is $err,                  q{},        'No stderr output';
  }; ## end 'Is listed beside the hand-written utilities' => sub
  subtest 'Matches the prebaked expression it was made from' => sub {
    my $sample = q{  Ação "Nº 3" <a\b|c> ＂＊／ 19  };
    my ( $exit, $out ) = capture_sub_output( sub { prebaked_list() } );
    my @names = decode( 'utf-8', $out ) =~ m{ ^ [ ]{2} (\S+) }gmsx;
    cmp_ok scalar @names, '>', 0, 'Prebaked expressions found to compare against';
    for my $name (@names) {
      ( my $fname = $name ) =~ tr{-}{_};
      my $p = params_get( '-p', $name, 'a' );
      is utils_get($fname)->($sample), $p->{exprs}[0]{func}->($sample), "$fname matches -p $name";
    }
  }; ## end 'Matches the prebaked expression it was made from' => sub
}; ## end 'prebaked utility functions' => sub


subtest 'transform_names' => sub {
  subtest 'Basic transformation' => sub {
    my $p = params_get( '-e', 's/foo/bar/', 'foo' );
    my ( $old, $new ) = transform_names($p);
    is_deeply $old, [qw{foo}], 'Old names preserved';
    is_deeply $new, [qw{bar}], 'New names transformed';
  }; ## end 'Basic transformation' => sub
  subtest 'Multiple files' => sub {
    my $p = params_get( '-e', 's/foo/bar/', qw{foo1 foo2} );
    my ( $old, $new ) = transform_names($p);
    is_deeply $old, [qw{foo1 foo2}], 'Multiple old names';
    is_deeply $new, [qw{bar1 bar2}], 'Multiple new names';
  }; ## end 'Multiple files' => sub
  subtest 'Check collisions enabled' => sub {
    my $p = params_get( '-e', 's/.*/same/', qw{file1 file2} );
    my ( $exit, $out, $err ) = capture_sub_output( sub { transform_names($p) } );
    is $exit, 255, 'Dies on collision';
    like $err, qr/Multiple files will be renamed/sm, 'Error message present';
  }; ## end 'Check collisions enabled' => sub
  subtest 'Check collisions disabled' => sub {
    my $p = params_get( '-e', 's/.*/same/', '--no-check-collisions', qw{file1 file2} );
    my ( $old, $new ) = transform_names($p);
    is_deeply $new, [qw{same same}], 'Collisions allowed when disabled';
  };
  subtest 'Soft collision handling' => sub {
    # Use a pattern that swaps names: A -> B, B -> A
    # Using tr to swap: A<->B
    my $p = params_get( '-e', 'tr/AB/BA/', qw{A B} );
    my ( $old, $new ) = transform_names($p);
    # A -> B, B -> A creates soft collision
    # Result: A -> temp, B -> A, temp -> B
    is scalar @{$old}, 3, 'Soft collision adds temp file';
    is scalar @{$new}, 3, 'Soft collision adds temp rename';
    ok $new->[0] =~ /\.tmp\z/sm, 'First file goes to temp';
    is $new->[1], 'A', 'Second file renamed to A';
    is $new->[2], 'B', 'Temp file renamed to B';
    ok $old->[2] =~ /\.tmp\z/sm, 'Temp file in old names';
  }; ## end 'Soft collision handling' => sub
}; ## end 'transform_names' => sub


subtest 'transform_name' => sub {
  subtest 'Basic transformations' => sub {
    my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', 'a' );
    is transform_name( $p, 'foo.txt' ), 'BAR.TXT', 'Basic transformations';
    $p = params_get( '-e', '$_ = $_."1"', '-e', '$_ = $_."2"', 'a' );
    is transform_name( $p, 'start' ), 'start12', 'Expressions execute in order';
  }; ## end 'Basic transformations' => sub
  subtest 'Filename components' => sub {
    subtest 'basename' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-b', 'a' );
      is transform_name( $p, '/path/foo.txt' ), '/path/BAR.TXT', 'Path untouched';
      is transform_name( $p, 'foo.txt' ),       'BAR.TXT',       'File with no path';
      is transform_name( $p, '/path/foo/' ),    '/path/BAR/',    'Slash at the end works';
    }; ## end 'basename' => sub
    subtest 'exclude_ext' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-x', 'a' );
      is transform_name( $p, 'foo.txt' ),      'BAR.txt',      'Simple ext';
      is transform_name( $p, 'file.tar.gz' ),  'FILE.tar.gz',  'Composite ext';
      is transform_name( $p, 'file.tar.gz/' ), 'FILE.tar.gz/', 'Composite ext dir';
      is transform_name( $p, 'foobar' ),       'BARBAR',       'No ext works fine';
      is transform_name( $p, '.foobar' ),      '.BARBAR',      'Dont mistake dotfile for ext';
      is transform_name( $p, '.tar.gz' ),      '.TAR.gz',      'Dont mistake dotfile for dbl ext';
    }; ## end 'exclude_ext' => sub
    subtest 'basename + exclude_ext' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-b', '-x', 'a' );
      is transform_name( $p, '/path/foo.txt' ),      '/path/BAR.txt',      'Path and ext untouched';
      is transform_name( $p, '/path/foo/' ),         '/path/BAR/',         'Slash at the end works';
      is transform_name( $p, 'foo.txt' ),            'BAR.txt',            'File with no path';
      is transform_name( $p, '/path/file.tar.gz' ),  '/path/FILE.tar.gz',  'Composite ext';
      is transform_name( $p, '/path/file.tar.gz/' ), '/path/FILE.tar.gz/', 'Composite ext dir';
      is transform_name( $p, '/path/foobar' ),       '/path/BARBAR',       'No ext works fine';
      is transform_name( $p, '/path/.foobar' ), '/path/.BARBAR', 'Dont mistake dotfile for ext';
      is transform_name( $p, '/path/.tar.gz' ), '/path/.TAR.gz', 'Dont mistake dotfile for dbl ext';
    }; ## end 'basename + exclude_ext' => sub
  }; ## end 'Filename components' => sub
  subtest 'Character encoding' => sub {
    ## no critic (ProhibitEscapedCharacters)
    my ( $p, $latin1_str, $utf8_str ) = ( undef, "caf\xe9", "caf\xc3\xa9" );
    ## use critic
    $p = params_get( '-e1', '--from-charset=latin1', '--to-charset=utf8', 'a' );
    is transform_name( $p, $latin1_str ), $utf8_str, 'Latin-1 to UTF-8 conversion';
    $p = params_get( '-e1', '--from-charset=utf-8', '--to-charset=latin1', 'a' );
    is transform_name( $p, $utf8_str ), $latin1_str, 'UTF-8 to Latin-1 conversion';
  }; ## end 'Character encoding' => sub
}; ## end 'transform_name' => sub


subtest 'check_hard_collisions' => sub {
  my @CASES = (
    [ 'no collision', [qw{a b}], [qw{c d}], q{}, q{}, 0 ],
    [
      'basic collision',
      [qw{a b}], [qw{c c}],
      <<~';;',
        Multiple files will be renamed to `c':
          - `a'
          - `b'
        Aborting due to collisions.
        ;;
      1
    ],
    [
      'multiple collisions',
      [qw{a b c}], [qw{d d d}],
      <<~';;',
        Multiple files will be renamed to `d':
          - `a'
          - `b'
          - `c'
        Aborting due to collisions.
        ;;
      1
    ],
    [ 'mixed collisions', [qw{a b c d}], [qw{x y x y}],
      <<~';;',
        Multiple files will be renamed to `x':
          - `a'
          - `c'
        Multiple files will be renamed to `y':
          - `b'
          - `d'
        Aborting due to collisions.
        ;;
      1
    ],
  );
  for my $case (@CASES) {
    my ( $name, $old, $new, $exp_err, $should_die ) = @{$case};
    subtest $name => sub {
      my ( $exit, $out, $err ) = capture_sub_output( sub { check_hard_collisions( $old, $new ) } );
      is $exit, $should_die ? 255 : 0, 'Correct exit status';
      is $out,  q{},                   'Stdout empty';
      is $err,  $exp_err,              'Stderr matches';
    }; ## end sub
  } ## end for my $case (@CASES)
}; ## end 'check_hard_collisions' => sub


subtest 'dodge_soft_collisions' => sub {
  my $tmpfunc = sub { state $counter = 0; return q{T} . $counter++; };
  my @CASES   = (
    'ABC  -> DEF'  => [qw{A B C}],   [qw{D E F}],   [qw{A B C}],            [qw{D E F}],
    'AB   -> BA'   => [qw{A B}],     [qw{B A}],     [qw{A B T0}],           [qw{T0 A B}],
    'AB   -> BC'   => [qw{A B}],     [qw{B C}],     [qw{A B T1}],           [qw{T1 C B}],
    'ABC  -> BCA'  => [qw{A B C}],   [qw{B C A}],   [qw{A B C T2 T3}],      [qw{T2 T3 A B C}],
    'ABCD -> BCDA' => [qw{A B C D}], [qw{B C D A}], [qw{A B C D T4 T5 T6}], [qw{T4 T5 T6 A B C D}],
  );
  for my ( $case, $input_old, $input_new, $expected_old, $expected_new ) (@CASES) {
    my ( $old, $new ) = dodge_soft_collisions( $input_old, $input_new, $tmpfunc );
    is_deeply [ $old, $new ], [ $expected_old, $expected_new ], $case;
  }
}; ## end 'dodge_soft_collisions' => sub


subtest 'mkdirp' => sub {
  # Test basic directory creation
  subtest 'Creates single directory' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/new_directory";
    ok !-e $dir, 'Directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Directory created successfully';
  }; ## end 'Creates single directory' => sub
  # Test nested directory creation
  subtest 'Creates nested directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/a/b/c/d";
    ok !-e $dir, 'Nested directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Deeply nested directory created';
  }; ## end 'Creates nested directories' => sub
  # Test idempotency - existing directory
  subtest 'Handles existing directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/existing";
    mkdir $dir;
    ok -d $dir, 'Directory exists before test';
    lives_ok { mkdirp($dir) } 'No error when directory exists';
    ok -d $dir, 'Directory remains intact';
  }; ## end 'Handles existing directories' => sub
  # Test partial existing structure
  subtest 'Completes partial structure' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    mkdir "$temp/existing_parent";
    my $dir = "$temp/existing_parent/new_child/grandchild";
    ok !-e $dir, 'Full path does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Creates missing child directories';
  }; ## end 'Completes partial structure' => sub
  subtest 'Fails if a file exists on the path' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    create_file("$temp/file.txt");
    throws_ok { mkdirp("$temp/file.txt") } qr/file exists/msi, 'Fails if a file exists';
  };
}; ## end 'mkdirp' => sub


subtest 'main function' => sub {
  subtest 'Help message' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--help}; main() } );
    is $exit, 0, 'Help exits successfully';
    like $out, qr/Usage: rpl/sm, 'Help message present';
  };
  subtest 'Version message' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--version}; main() } );
    is $exit, 0, 'Version exits successfully';
    like $out, qr/rpl v\d+\.\d+\.\d+/sm, 'Version message present';
  };
  subtest 'List prebaked' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--list-prebaked}; main() } );
    is $exit, 0, 'List-prebaked exits successfully';
    like $out, qr/The following prebaked expressions are available:/sm, 'List output present';
  };
  subtest 'List utils' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--list-utils}; main() } );
    is $exit, 0, 'List-utils exits successfully';
    like $out, qr/The following utility functions are available:/sm, 'List output present';
    like $out, qr/to_roman/sm,                                       'Lists to_roman';
    like $out, qr/from_roman/sm,                                     'Lists from_roman';
  }; ## end 'List utils' => sub
  # Characterization test: this behaviour predates --util (transform_names
  # computes every new name before perform_renames runs), but the README now
  # promises it for failing utility functions, so it is pinned here.
  subtest 'A failing utility aborts before renaming anything' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    create_file( "$temp/ch 1.txt", 'one' );
    create_file( "$temp/ch 0.txt", 'zero' );
    create_file( "$temp/ch 5.txt", 'five' );
    my ( $exit, $out, $err ) = run_script(
      { cwd => $temp },
      '-au',      'to_roman', '-e', 's/(\d+)/to_roman($1)/e',
      'ch 1.txt', 'ch 0.txt', 'ch 5.txt',
    );
    is $exit, 1, 'Exits with an error';
    like $err, qr/ch\ 0\.txt/msx,       'Error names the offending file';
    like $err, qr/not\ an\ integer/msx, 'Error explains why';
    assert_file_content( "$temp/ch 1.txt", 'one' );
    assert_file_content( "$temp/ch 5.txt", 'five' );
    ok !-e "$temp/ch I.txt", 'Renameable file left untouched';
    ok !-e "$temp/ch V.txt", 'Later renameable file left untouched';
  }; ## end 'A failing utility aborts before renaming anything' => sub
  subtest 'Dry run output' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-es/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 0, 'Dry run exits successfully';
    like $out, qr/`foo\.txt' -> `bar\.txt'/sm, 'Transformation shown';
  }; ## end 'Dry run output' => sub
  subtest 'Quiet mode' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-qes/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 0,   'Quiet mode exits successfully';
    is $out,  q{}, 'No output in quiet mode';
  }; ## end 'Quiet mode' => sub
  subtest 'No changes output' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file( "$temp/foo.txt", 'test content' );
    my $new_file = "$temp/bar.txt";
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-es/foo/bar/', 'bar.txt' );
        main();
      }
    );
    assert_file_content( $old_file, 'test content' );
    ok !-e $new_file, 'Target file does not exist';
    is $exit, 0,   'No changes exits successfully';
    is $out,  q{}, 'No output when no changes';
  }; ## end 'No changes output' => sub
  subtest 'Basic rename with apply' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file( "$temp/foo.txt", 'test content' );
    my $new_file = "$temp/bar.txt";
    create_file( $old_file, 'test content' );
    ok -e $old_file,  'Source file exists';
    ok !-e $new_file, 'Target file does not exist initially';
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 0, 'Rename exits successfully';
    ok !-e $old_file, 'Source file renamed away';
    ok -e $new_file,  'Target file exists after rename';
    assert_file_content( $new_file, 'test content' );
  }; ## end 'Basic rename with apply' => sub
  subtest 'Multiple files with apply' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt", "$temp/file3.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt",  "$temp/doc3.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/file/doc/', 'file1.txt', 'file2.txt', 'file3.txt' );
        main();
      }
    );
    is $exit, 0, 'Multiple renames exit successfully';
    for ( 0 .. $#old_files ) {
      ok !-e $old_files[$_], "Source file $old_files[$_] renamed away";
      assert_file_content( $new_files[$_], "content for $old_files[$_]" );
    }
  }; ## end 'Multiple files with apply' => sub
  subtest 'Apply with mkdirp' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file("$temp/source.txt");
    my $new_file = "$temp/newdir/subdir/target.txt";
    ok !-d "$temp/newdir", 'Target directory does not exist initially';
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-ames/source/target/;s|^|newdir/subdir/|', 'source.txt' );
        main();
      }
    );
    is $exit, 0, 'Rename with mkdirp exits successfully';
    ok -d "$temp/newdir/subdir", 'Subdirectory created';
    ok -e $new_file,             'File renamed to new directory';
    ok !-e $old_file,            'Source file renamed away';
  }; ## end 'Apply with mkdirp' => sub
  subtest 'Apply with overwrite' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file( "$temp/old.txt", 'old content' );
    my $new_file = create_file( "$temp/new.txt", 'new content' );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aoes/old/new/', 'old.txt' );
        main();
      }
    );
    is $exit, 0, 'Rename with overwrite exits successfully';
    ok -e $new_file,  'Target file still exists';
    ok !-e $old_file, 'Source file renamed away';
    assert_file_content( $new_file, 'old content' );
  }; ## end 'Apply with overwrite' => sub
  subtest 'Error: source does not exist' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my ( $exit, $out, $err ) = run_script( { cwd => $temp }, '-aes/foo/bar/', 'foo.txt' );
    is $exit, 1, 'Exits with error when source does not exist';
    is $err,  "Error: source file `foo.txt' does not exist.\n", 'Error message present';
  }; ## end 'Error: source does not exist' => sub
  subtest 'Error: target exists without overwrite' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file("$temp/old.txt");
    my $new_file = create_file("$temp/new.txt");
    my ( $exit, $out, $err ) = run_script( { cwd => $temp }, '-aes/old/new/', 'old.txt' );
    is $exit, 1, 'Exits with error when target exists';
    is $err,  "Error: target file `new.txt' already exists.\n", 'Error message present';
    ok -e $old_file, 'Source file not renamed';
    ok -e $new_file, 'Target file still exists';
  }; ## end 'Error: target exists without overwrite' => sub
  subtest 'Apply with soft collision handling' => sub {
    my $temp   = tempdir( CLEANUP => 1 );
    my $file_a = create_file( "$temp/A", 'content A' );
    my $file_b = create_file( "$temp/B", 'content B' );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aetr/AB/BA/', 'A', 'B' );
        main();
      }
    );
    is $exit, 0, 'Swap rename exits successfully';
    assert_file_content( $file_b, 'content A' );
    assert_file_content( $file_a, 'content B' );
  }; ## end 'Apply with soft collision handling' => sub
  subtest 'Charset conversion latin1 -> utf-8' => sub {
    my $utf8   = Encode::find_encoding('utf-8');
    my $latin1 = Encode::find_encoding('latin1');
    my $cwd    = Cwd::getcwd();
    my $temp   = tempdir( CLEANUP => 1 );
    chdir $temp or die;
    my $old_file_bytes = $latin1->encode('café.txt');
    create_file( $old_file_bytes, 'test content' );
    my $utf8_bytes = $utf8->encode('café.txt');
    ok $old_file_bytes ne $utf8_bytes, 'old file bytes differ from UTF-8 bytes';
    ok !-e 'café.txt',                 'café.txt does not exist';
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-a', '-c', 'latin1', $old_file_bytes );
        main();
      }
    );
    is $exit, 0, 'Charset conversion exits successfully';
    ok !-e $old_file_bytes, 'Source file renamed away';
    assert_file_content( 'café.txt', 'test content' );
    chdir $cwd or die;
  }; ## end 'Charset conversion latin1 -> utf-8' => sub
  subtest 'Charset conversion utf-8 -> latin1' => sub {
    my $utf8   = Encode::find_encoding('utf-8');
    my $latin1 = Encode::find_encoding('latin1');
    my $cwd    = Cwd::getcwd();
    my $temp   = tempdir( CLEANUP => 1 );
    chdir $temp or die;
    my $old_file = create_file( 'café.txt', 'test content' );
    my $new_file = $latin1->encode( $utf8->decode('café.txt') );
    ok $old_file ne $new_file, 'old file bytes differ from latin1 bytes';
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-atlatin1', 'café.txt' );
        main();
      }
    );
    is $exit, 0, 'Charset conversion exits successfully';
    ok !-e $old_file, 'Source file renamed away';
    assert_file_content( $new_file, 'test content' );
    chdir $cwd or die;
  }; ## end 'Charset conversion utf-8 -> latin1' => sub
  subtest 'Script from file' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file( "$temp/FOO.txt", 'test content' );
    my $new_file = "$temp/bar.txt";
    my $script   = create_tempfile( ['tr/A-Z/a-z/; s/foo/bar/'] );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( "-as$script", 'FOO.txt' );
        main();
      }
    );
    is $exit, 0, 'Script from file exits successfully';
    ok !-e $old_file, 'Source file renamed away';
    ok -e $new_file,  'Target file exists after rename';
    assert_file_content( $new_file, 'test content' );
  }; ## end 'Script from file' => sub
  subtest 'Script from stdin' => sub {
    my $temp           = tempdir( CLEANUP => 1 );
    my $old_file       = create_file( "$temp/FOO.txt", 'test content' );
    my $new_file       = "$temp/bar.txt";
    my $script_content = 'tr/A-Z/a-z/; s/foo/bar/';
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        open STDIN, '<', create_tempfile( [$script_content] );
        local @ARGV = ( '-s-', 'FOO.txt' );
        main();
      } ## end sub
    );
    is $exit, 0, 'Script from stdin exits successfully';
    like $out, qr/`FOO\.txt' -> `bar\.txt'/sm, 'Transformation shown';
  }; ## end 'Script from stdin' => sub
  subtest 'From-file' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my $file_list = create_tempfile( [qw{file1.txt file2.txt}] );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/file/doc/', "-f$file_list" );
        main();
      }
    );
    is $exit, 0, 'From-file exits successfully';
    for ( 0 .. $#old_files ) {
      ok !-e $old_files[$_], "Source file $old_files[$_] renamed away";
      assert_file_content( $new_files[$_], "content for $old_files[$_]" );
    }
  }; ## end 'From-file' => sub
  subtest 'From-file from stdin' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        open STDIN, '<', create_tempfile( [qw{file1.txt file2.txt}] );
        local @ARGV = ( '-es/file/doc/', '-f-' );
        main();
      } ## end sub
    );
    is $exit, 0, 'From-file from stdin exits successfully';
    like $out, qr/`file1\.txt' -> `doc1\.txt'/sm, 'First transformation shown';
    like $out, qr/`file2\.txt' -> `doc2\.txt'/sm, 'Second transformation shown';
  }; ## end 'From-file from stdin' => sub
  subtest 'From-file with custom delimiter' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my $file_list = create_tempfile( [qw{file1.txt file2.txt}], q{:} );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/file/doc/', '--delim=:', "-f$file_list" );
        main();
      }
    );
    is $exit, 0, 'From-file with custom delimiter exits successfully';
    for ( 0 .. $#old_files ) {
      ok !-e $old_files[$_], "Source file $old_files[$_] renamed away";
      assert_file_content( $new_files[$_], "content for $old_files[$_]" );
    }
  }; ## end 'From-file with custom delimiter' => sub
  subtest 'From-file with null delimiter' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my $file_list = create_tempfile( [qw{file1.txt file2.txt}], "\0" );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/file/doc/', '--null', "-f$file_list" );
        main();
      }
    );
    is $exit, 0, 'From-file with null delimiter exits successfully';
    for ( 0 .. $#old_files ) {
      ok !-e $old_files[$_], "Source file $old_files[$_] renamed away";
      assert_file_content( $new_files[$_], "content for $old_files[$_]" );
    }
  }; ## end 'From-file with null delimiter' => sub
  subtest 'From-file with null delimiter from stdin' => sub {
    my $temp      = tempdir( CLEANUP => 1 );
    my @old_files = ( "$temp/file1.txt", "$temp/file2.txt" );
    my @new_files = ( "$temp/doc1.txt",  "$temp/doc2.txt" );
    create_file( $_, "content for $_" ) for @old_files;
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        open STDIN, '<', create_tempfile( [qw{file1.txt file2.txt}], "\0" );
        local @ARGV = ( '-es/file/doc/', '--null', '-f-' );
        main();
      } ## end sub
    );
    is $exit, 0, 'From-file with null delimiter from stdin exits successfully';
    like $out, qr/`file1\.txt' -> `doc1\.txt'/sm, 'First transformation shown';
    like $out, qr/`file2\.txt' -> `doc2\.txt'/sm, 'Second transformation shown';
  }; ## end 'From-file with null delimiter from stdin' => sub
}; ## end 'main function' => sub


# Exact-match assertions on rendered stderr. The rest of the suite uses loose
# `like' matches, which pass regardless of trailing junk (a leaked script path,
# a stray blank line), so the formatting contract needs pinning down here.
subtest 'error message formatting' => sub {
  subtest 'Usage error is prefixed and hinted, without a leaked script path' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = qw{ -p nonexistent a };
        main();
      }
    );
    is $err, <<~';;', 'Usage error rendered without Perl location suffix';
      Error: unknown prebaked expression: nonexistent.
      Try `rpl --help' for more information.
      ;;
  }; ## end 'Usage error is prefixed and hinted, without a leaked script path' => sub

  subtest 'Runtime expression failure is prefixed, without a trailing blank line' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-e', 'die "boom\n"', 'foo.txt' );
        main();
      }
    );
    is $err, <<~';;', 'Runtime error prefixed and not double-spaced';
      Error: expression 'die "boom\n"' failed on 'foo.txt': boom.
      ;;
  }; ## end 'Runtime expression failure is prefixed, without a trailing blank line' => sub

  subtest 'Collision abort is prefixed but not hinted' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-e', 's/.*/same.txt/', 'x1.txt', 'x2.txt' );
        main();
      }
    );
    is $err, <<~';;', 'Collision abort carries no --help hint';
      Multiple files will be renamed to `same.txt':
        - `x1.txt'
        - `x2.txt'
      Error: aborting due to collisions.
      ;;
  }; ## end 'Collision abort is prefixed but not hinted' => sub
}; ## end 'error message formatting' => sub


subtest 'exit codes' => sub {
  subtest 'Successful runs exit 0' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    create_file( "$temp/a.txt", 'content' );

    my ($dry) = run_script( { cwd => $temp }, '-e', 's/a/b/', 'a.txt' );
    is $dry, 0, 'Dry run exits 0';

    my ($noop) = run_script( { cwd => $temp }, '-e', 's/zzz/q/', 'a.txt' );
    is $noop, 0, 'Run matching nothing exits 0';

    my ($apply) = run_script( { cwd => $temp }, '-a', '-e', 's/a/b/', 'a.txt' );
    is $apply, 0, 'Applied rename exits 0';
    ok -e "$temp/b.txt", 'Applied rename actually happened';
  }; ## end 'Successful runs exit 0' => sub

  subtest 'Informational options exit 0' => sub {
    for my $opt (qw{ --help --version --list-prebaked }) {
      my ($exit) = run_script( {}, $opt );
      is $exit, 0, "$opt exits 0";
    }
  }; ## end 'Informational options exit 0' => sub

  subtest 'Failing runs exit 1' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    create_file( "$temp/a.txt",  'content' );
    create_file( "$temp/a1.txt", 'one' );
    create_file( "$temp/a2.txt", 'two' );

    my @CASES = (
      [ 'Unknown option',              ['--nosuchflag'] ],
      [ 'No expressions given',        ['a.txt'] ],
      [ 'No files given',              [ '-e', 's/a/b/' ] ],
      [ 'Unknown charset',             [ '-c', 'nosuchcharset',  '-e', 's/a/b/', 'a.txt' ] ],
      [ 'Missing --from-file target',  [ '-e', 's/a/b/',         '-f', 'nosuchfile.txt' ] ],
      [ 'Uncompilable expression',     [ '-e', 's/a/b/(',        'a.txt' ] ],
      [ 'Expression dying at runtime', [ '-e', 'die "boom\n"',   'a.txt' ] ],
      [ 'Target name collision',       [ '-e', 's/\d//',         'a1.txt', 'a2.txt' ] ],
      [ 'Unknown prebaked expression', [ '-p', 'nosuchprebaked', 'a.txt' ] ],
    );
    for my $case (@CASES) {
      my ( $name, $args ) = @{$case};
      my ( $exit, $out, $err ) = run_script( { cwd => $temp }, @{$args} );
      is $exit,  1,   "$name exits 1";
      isnt $err, q{}, "$name explains itself on stderr";
      unlike $err, qr/at \S+ line \d+/sm, "$name reports without leaking a source location";
    } ## end for my $case (@CASES)
  }; ## end 'Failing runs exit 1' => sub
}; ## end 'exit codes' => sub


done_testing;

1;
