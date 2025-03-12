#!/usr/bin/env perl

use 5.036;
use strict;
use warnings;
use utf8;
use autodie;

use English '-no_match_vars';
use Test::More;
use Test::Exception;
use File::Temp qw{tempfile tempdir};

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
  my ( $content, $delim )    = @_;
  my ( $fh,      $filename ) = tempfile( UNLINK => 1 );
  print {$fh} join( $delim // "\n", @{$content} );
  close $fh;
  return $filename;
} ## end sub create_tempfile


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
      is transform_name( $p, '/path/foo.txt' ), '/path/BAR.TXT', 'path untouched';
      is transform_name( $p, 'foo.txt' ),       'BAR.TXT',       'file with no path';
      is transform_name( $p, '/path/foo/' ),    '/path/BAR/',    'slash at the end works';
    };
    subtest 'exclude_ext' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-x', 'a' );
      is transform_name( $p, 'foo.txt' ),      'BAR.txt',      'simple ext';
      is transform_name( $p, 'file.tar.gz' ),  'FILE.tar.gz',  'composite ext';
      is transform_name( $p, 'file.tar.gz/' ), 'FILE.tar.gz/', 'composite ext dir';
      is transform_name( $p, 'foobar' ),       'BARBAR',       'no ext works fine';
      is transform_name( $p, '.foobar' ),      '.BARBAR',      'dont mistake dotfile for ext';
      is transform_name( $p, '.tar.gz' ),      '.TAR.gz',      'dont mistake dotfile for dbl ext';
    };
    subtest 'basename + exclude_ext' => sub {
      my $p = params_get( '-e', 's/foo/bar/', '-e', '$_ = uc $_', '-b', '-x', 'a' );
      is transform_name( $p, '/path/foo.txt' ),      '/path/BAR.txt',      'path and ext untouched';
      is transform_name( $p, '/path/foo/' ),         '/path/BAR/',         'slash at the end works';
      is transform_name( $p, 'foo.txt' ),            'BAR.txt',            'file with no path';
      is transform_name( $p, '/path/file.tar.gz' ),  '/path/FILE.tar.gz',  'composite ext';
      is transform_name( $p, '/path/file.tar.gz/' ), '/path/FILE.tar.gz/', 'composite ext dir';
      is transform_name( $p, '/path/foobar' ),       '/path/BARBAR',       'no ext works fine';
      is transform_name( $p, '/path/.foobar' ), '/path/.BARBAR', 'dont mistake dotfile for ext';
      is transform_name( $p, '/path/.tar.gz' ), '/path/.TAR.gz', 'dont mistake dotfile for dbl ext';
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
      is $exit, $should_die ? 255 : 0, 'correct exit status';
      is $out,  q{},                   'stdout empty';
      is $err,  $exp_err,              'stderr matches';
    };
  } ## end for my $case (@CASES)
};

subtest 'mkdirp' => sub {
  # Test basic directory creation
  subtest 'creates single directory' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/new_directory";
    ok !-e $dir, 'directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'directory created successfully';
  };
  # Test nested directory creation
  subtest 'creates nested directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/a/b/c/d";
    ok !-e $dir, 'nested directory does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'deeply nested directory created';
  };
  # Test idempotency - existing directory
  subtest 'handles existing directories' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    my $dir  = "$temp/existing";
    mkdir $dir;
    ok -d $dir, 'directory exists before test';
    lives_ok { mkdirp($dir) } 'no error when directory exists';
    ok -d $dir, 'directory remains intact';
  };
  # Test partial existing structure
  subtest 'completes partial structure' => sub {
    my $temp = tempdir( CLEANUP => 1 );
    mkdir "$temp/existing_parent";
    my $dir = "$temp/existing_parent/new_child/grandchild";
    ok !-e $dir, 'full path does not exist initially';
    mkdirp($dir);
    ok -d $dir, 'creates missing child directories';
  };
};


done_testing;


1;
