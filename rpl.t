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
  };
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
  };
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
      }
    } ## end for my $dir (qw{ from to })
  };
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
      }
    } ## end for my ( $long, $short,...)
  };
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
  };
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
    };
    subtest 'Quiet flag' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-q', 'a' );
      is $p->{verbosity}, 0, 'Single -q decreases verbosity';
      $p = params_get( '-e', 's/foo/bar/', '-q', '-q', 'a' );
      is $p->{verbosity}, 0, 'Verbosity clamped to 0';
    };
    subtest 'Verbose and quiet together' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-v', '-q', 'a' );
      is $p->{verbosity}, 1, 'Verbose and quiet cancel';
      $p = params_get( '-e', 's/foo/bar/', '-v', '-v', '-q', 'a' );
      is $p->{verbosity}, 2, 'Multiple verbose and quiet (2v - 1q = 1, but starts at 1)';
    };
  };
};


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
  };
  subtest 'Error handling' => sub {
    throws_ok { read_file( 'nonexistent-file', "\n" ) } qr/can't open file/ism, 'File not found';
    throws_ok { read_file( create_tempfile( ['test'] ), 'ab' ) } qr/invalid delimiter/ism, 'Invalid delimiter length';
  };
};


subtest 'compile_exprs' => sub {
  subtest 'Compiles single expression' => sub {
    my $exprs = compile_exprs('s/foo/bar/');
    is scalar @{$exprs},           1,            'One expression compiled';
    is $exprs->[0]{expr},          's/foo/bar/', 'Expression preserved';
    is $exprs->[0]{func}->('foo'), 'bar',        'Function works';
  };
  subtest 'Compiles multiple expressions' => sub {
    my $exprs = compile_exprs( 's/foo/bar/', 's/bar/baz/' );
    is scalar @{$exprs},           2,     'Two expressions compiled';
    is $exprs->[0]{func}->('foo'), 'bar', 'First function works';
    is $exprs->[1]{func}->('bar'), 'baz', 'Second function works';
  };
  subtest 'Handles UTF-8 expressions' => sub {
    my $exprs = compile_exprs('s/foo/世界/');
    is $exprs->[0]{func}->('foo'), '世界', 'UTF-8 expression works';
  };
  subtest 'Error handling' => sub {
    throws_ok { compile_exprs('BEGIN{die "test"}') } qr/compilation failed/ism, 'Compilation error';
  };
};


subtest 'prebaked_get' => sub {
  subtest 'Gets known prebaked expression' => sub {
    my $expr = prebaked_get('trim');
    like $expr, qr/s\/.*\s/sm, 'Returns expression string with substitution';
    ok length $expr > 0, 'Expression is not empty';
  };
  subtest 'Error handling' => sub {
    throws_ok { prebaked_get('nonexistent') } qr/unknown prebaked expression/ism, 'Unknown expression';
  };
};


subtest 'prebaked_list' => sub {
  my ( $exit, $out, $err ) = capture_sub_output( sub { prebaked_list() } );
  is $exit, 0, 'Exits successfully';
  like $out, qr/The following prebaked expressions are available:/sm, 'Header present';
  like $out, qr/collapse-blanks/sm,                                   'Lists collapse-blanks';
  like $out, qr/trim/sm,                                              'Lists trim';
  like $out, qr/strip-diacritics/sm,                                  'Lists strip-diacritics';
  is $err, q{}, 'No stderr output';
};


subtest 'prebaked exprs' => sub {
  ## no critic (ProhibitEscapedCharacters)
  my @CASES = (
    [ 'collapse-blanks',       " a  \t\x{2003} \n b\tc ", 'a b c' ],
    [ 'normalize-nfc',         "Ａa\x{0301}",              q{Ａá} ],
    [ 'normalize-nfd',         q{Ａá},                     "Ａa\x{0301}" ],
    [ 'normalize-nfkc',        "ＡＡ\x{0301}",              'AÁ' ],
    [ 'normalize-nfkd',        'Ａá',                      "Aa\x{0301}" ],
    [ 'strip-diacritics',      'áéíóúý',                  'aeiouy' ],
    [ 'trim',                  "  \t\n  hello  \t\n  ",   'hello' ],
    [ 'unidecode',             'Христос—αἰώνιον 道',       'Khristos--aionion Dao ' ],
    [ 'windows-fullwidth',     '\\/:"<>|?*',              '＼/：＂＜＞｜？＊' ],
    [ 'windows-fullwidth-rev', '＼/：＂＜＞｜？＊',               '\\/:"<>|?*' ],
  );
  for my $case (@CASES) {
    my ( $name, $input, $output ) = @{$case};
    my $p = params_get( "--prebaked=$name", 'a' );
    is $p->{exprs}[0]{func}->($input), $output, "$name works";
  }
};


subtest 'transform_names' => sub {
  subtest 'Basic transformation' => sub {
    my $p = params_get( '-e', 's/foo/bar/', 'foo' );
    my ( $old, $new ) = transform_names($p);
    is_deeply $old, [qw{foo}], 'Old names preserved';
    is_deeply $new, [qw{bar}], 'New names transformed';
  };
  subtest 'Multiple files' => sub {
    my $p = params_get( '-e', 's/foo/bar/', qw{foo1 foo2} );
    my ( $old, $new ) = transform_names($p);
    is_deeply $old, [qw{foo1 foo2}], 'Multiple old names';
    is_deeply $new, [qw{bar1 bar2}], 'Multiple new names';
  };
  subtest 'Check collisions enabled' => sub {
    my $p = params_get( '-e', 's/.*/same/', qw{file1 file2} );
    my ( $exit, $out, $err ) = capture_sub_output( sub { transform_names($p) } );
    is $exit, 255, 'Dies on collision';
    like $err, qr/Multiple files will be renamed/sm, 'Error message present';
  };
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
  };
};


subtest 'transform_name' => sub {
  subtest 'Basic transformations' => sub {
    my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', 'a' );
    is transform_name( $p, 'foo.txt' ), 'BAR.TXT', 'Basic transformations';
    $p = params_get( '-e', '$_ = $_."1"', '-e', '$_ = $_."2"', 'a' );
    is transform_name( $p, 'start' ), 'start12', 'Expressions execute in order';
  };
  subtest 'Filename components' => sub {
    subtest 'basename' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-b', 'a' );
      is transform_name( $p, '/path/foo.txt' ), '/path/BAR.TXT', 'Path untouched';
      is transform_name( $p, 'foo.txt' ),       'BAR.TXT',       'File with no path';
      is transform_name( $p, '/path/foo/' ),    '/path/BAR/',    'Slash at the end works';
    };
    subtest 'exclude_ext' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-x', 'a' );
      is transform_name( $p, 'foo.txt' ),      'BAR.txt',      'Simple ext';
      is transform_name( $p, 'file.tar.gz' ),  'FILE.tar.gz',  'Composite ext';
      is transform_name( $p, 'file.tar.gz/' ), 'FILE.tar.gz/', 'Composite ext dir';
      is transform_name( $p, 'foobar' ),       'BARBAR',       'No ext works fine';
      is transform_name( $p, '.foobar' ),      '.BARBAR',      'Dont mistake dotfile for ext';
      is transform_name( $p, '.tar.gz' ),      '.TAR.gz',      'Dont mistake dotfile for dbl ext';
    };
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
    };
  };
  subtest 'Character encoding' => sub {
    ## no critic (ProhibitEscapedCharacters)
    my ( $p, $latin1_str, $utf8_str ) = ( undef, "caf\xe9", "caf\xc3\xa9" );
    ## use critic
    $p = params_get( '-e1', '--from-charset=latin1', '--to-charset=utf8', 'a' );
    is transform_name( $p, $latin1_str ), $utf8_str, 'Latin-1 to UTF-8 conversion';
    $p = params_get( '-e1', '--from-charset=utf-8', '--to-charset=latin1', 'a' );
    is transform_name( $p, $utf8_str ), $latin1_str, 'UTF-8 to Latin-1 conversion';
  };
};


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
    };
  } ## end for my $case (@CASES)
};


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
};


subtest 'mkdirp' => sub {
  # Test basic directory creation
  subtest 'Creates single directory' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/new_directory";
    ok !-e $dir, 'Directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Directory created successfully';
  };
  # Test nested directory creation
  subtest 'Creates nested directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/a/b/c/d";
    ok !-e $dir, 'Nested directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Deeply nested directory created';
  };
  # Test idempotency - existing directory
  subtest 'Handles existing directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/existing";
    mkdir $dir;
    ok -d $dir, 'Directory exists before test';
    lives_ok { mkdirp($dir) } 'No error when directory exists';
    ok -d $dir, 'Directory remains intact';
  };
  # Test partial existing structure
  subtest 'Completes partial structure' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    mkdir "$temp/existing_parent";
    my $dir = "$temp/existing_parent/new_child/grandchild";
    ok !-e $dir, 'Full path does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'Creates missing child directories';
  };
  subtest 'Fails if a file exists on the path' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    create_file("$temp/file.txt");
    throws_ok { mkdirp("$temp/file.txt") } qr/file exists/msi, 'Fails if a file exists';
  };
};


subtest 'main function' => sub {
  subtest 'Help message' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--help}; main() } );
    is $exit, 0, 'Help exits successfully';
    like $out, qr/Usage: rpl/sm, 'Help message present';
  };
  subtest 'Version message' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--version}; main() } );
    is $exit, 0, 'Version exits successfully';
    like $out, qr/rpl v3\.1\.0/sm, 'Version message present';
  };
  subtest 'List prebaked' => sub {
    my ( $exit, $out, $err ) = capture_sub_output( sub { local @ARGV = qw{--list-prebaked}; main() } );
    is $exit, 0, 'List-prebaked exits successfully';
    like $out, qr/The following prebaked expressions are available:/sm, 'List output present';
  };
  subtest 'Dry run output' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-es/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 0, 'Dry run exits successfully';
    like $out, qr/`foo\.txt' -> `bar\.txt'/sm, 'Transformation shown';
  };
  subtest 'Quiet mode' => sub {
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        local @ARGV = ( '-qes/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 0,   'Quiet mode exits successfully';
    is $out,  q{}, 'No output in quiet mode';
  };
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
  };
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
  };
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
  };
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
  };
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
  };
  subtest 'Error: source does not exist' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/foo/bar/', 'foo.txt' );
        main();
      }
    );
    is $exit, 255, 'Exits with error when source does not exist';
    like $err, qr/Source file.*does not exist/sm, 'Error message present';
  };
  subtest 'Error: target exists without overwrite' => sub {
    my $temp     = tempdir( CLEANUP => 1 );
    my $old_file = create_file("$temp/old.txt");
    my $new_file = create_file("$temp/new.txt");
    my ( $exit, $out, $err ) = capture_sub_output(
      sub {
        chdir $temp or die;
        local @ARGV = ( '-aes/old/new/', 'old.txt' );
        main();
      }
    );
    is $exit, 255, 'Exits with error when target exists';
    like $err, qr/Target file.*already exists/sm, 'Error message present';
    ok -e $old_file, 'Source file not renamed';
    ok -e $new_file, 'Target file still exists';
  };
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
  };
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
  };
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
  };
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
  };
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
      }
    );
    is $exit, 0, 'Script from stdin exits successfully';
    like $out, qr/`FOO\.txt' -> `bar\.txt'/sm, 'Transformation shown';
  };
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
  };
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
      }
    );
    is $exit, 0, 'From-file from stdin exits successfully';
    like $out, qr/`file1\.txt' -> `doc1\.txt'/sm, 'First transformation shown';
    like $out, qr/`file2\.txt' -> `doc2\.txt'/sm, 'Second transformation shown';
  };
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
  };
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
  };
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
      }
    );
    is $exit, 0, 'From-file with null delimiter from stdin exits successfully';
    like $out, qr/`file1\.txt' -> `doc1\.txt'/sm, 'First transformation shown';
    like $out, qr/`file2\.txt' -> `doc2\.txt'/sm, 'Second transformation shown';
  };
};


done_testing;

1;
