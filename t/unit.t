#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

# ------ Load the dless script without running _main() ------------------------------
# The `unless (caller())` guard in dless prevents _main() from running when
# the file is loaded via `do`.
my $dless = "$Bin/../dless";
do $dless or die "Could not load $dless: $@";

# ------ Helpers ------------------------------
sub strip_ansi { (my $s = $_[0]) =~ s/\e\[[0-9;]*[mABCDHJKfsuhl]//g; $s }

# ------------------------------
# clamp()
# ------------------------------
subtest 'clamp' => sub {
    is(clamp(5,  0, 10), 5,  'within range');
    is(clamp(-1, 0, 10), 0,  'below min clamps to min');
    is(clamp(11, 0, 10), 10, 'above max clamps to max');
    is(clamp(0,  0,  0), 0,  'min == max == val');
    is(clamp(0,  0, 10), 0,  'exactly at min');
    is(clamp(10, 0, 10), 10, 'exactly at max');
};

# ------------------------------
# format_cell()
# ------------------------------
subtest 'format_cell --- left-align (text)' => sub {
    is(format_cell('hello', 10, 0), 'hello     ', 'padded right with spaces');
    is(format_cell('hello', 5,  0), 'hello',      'exact fit, no padding');
    is(format_cell('',      4,  0), '    ',        'empty string padded');
    is(format_cell(undef,   4,  0), '    ',        'undef treated as empty');
};

subtest 'format_cell --- right-align (numeric)' => sub {
    is(format_cell('42', 6, 1), '    42', 'right-aligned number');
    is(format_cell('42', 2, 1), '42',     'exact fit, no padding');
    is(format_cell('',   4, 1), '    ',   'empty string padded');
};

subtest 'format_cell --- truncation' => sub {
    is(format_cell('toolong', 5, 0), 'tool>', 'truncated with > for text');
    is(format_cell('toolong', 5, 1), 'tool>', 'truncated with > for numeric');
    is(length(format_cell('toolong', 5, 0)), 5, 'truncated result is exactly width');
};

# ------------------------------
# clip_content()
# ------------------------------
subtest 'clip_content' => sub {
    my $content = 'ABCDEFGHIJ';  # 10 chars

    is(clip_content($content, 0, 5),  'ABCDE',      'no offset, clips to width');
    is(clip_content($content, 3, 5),  'DEFGH',      'offset 3, clips to width');
    is(clip_content($content, 0, 15), 'ABCDEFGHIJ     ', 'pads when shorter than width');
    is(clip_content($content, 8, 5),  'IJ   ',      'partial content + padding');
    is(clip_content($content, 20, 5), '     ',      'offset past end --- all spaces');
    is(length(clip_content($content, 0, 7)),  7, 'result is exactly width when longer');
    is(length(clip_content($content, 0, 15)), 15, 'result is exactly width when shorter');
};

# ------------------------------
# compute_col_widths()
# ------------------------------
subtest 'compute_col_widths' => sub {
    my $header = ['name', 'age', 'score'];
    my @rows = (
        ['Alice', '30',  '98.5'],
        ['Bob',   '250', '7'],
        ['Carol', '42',  '88.3333'],
    );

    my $widths = compute_col_widths(\@rows, $header, 3, undef);

    is($widths->[0], 5, 'col 0: max(name=4, Alice=5, Bob=3, Carol=5) = 5');
    is($widths->[1], 3, 'col 1: max(age=3, 30=2, 250=3, 42=2) = 3');
    is($widths->[2], 7, 'col 2: max(score=5, 98.5=4, 7=1, 88.3333=7) = 7');
};

subtest 'compute_col_widths --- minimum width from column number' => sub {
    # Column 10 needs at least 2 chars for the column number "10"
    my $header = [map { "c$_" } (1..10)];
    my @rows   = ([map { 'x' } (1..10)]);
    my $widths = compute_col_widths(\@rows, $header, 10, undef);

    is($widths->[0], 2, 'col 1: min width = max(c1=2, x=1, colnum=1) = 2');
    is($widths->[9], 3, 'col 10: min width = max(c10=3, x=1, colnum=2) = 3');
};

subtest 'compute_col_widths --- limit respected' => sub {
    my $header = ['val'];
    my @rows   = (
        ['short'],           # row 0
        ['a_very_long_val'], # row 1 --- should be ignored with limit=1
    );
    my $widths_limited  = compute_col_widths(\@rows, $header, 1, 1);
    my $widths_all      = compute_col_widths(\@rows, $header, 1, undef);

    is($widths_limited->[0], 5, 'limit=1: only sees "short" (5 chars)');
    is($widths_all->[0],    15, 'no limit: sees "a_very_long_val" (15 chars)');
};

# ------------------------------
# detect_numeric()
# ------------------------------
subtest 'detect_numeric --- all numeric' => sub {
    my @rows = (['1', '2.5', '-3', '+4', '1e5', '1.2E-3', '0']);
    my $flags = detect_numeric(\@rows, 7, undef);
    ok($flags->[$_], "col $_ is numeric") for 0..6;
};

subtest 'detect_numeric --- text column' => sub {
    my @rows = (['Alice', 'Bob', 'Carol']);
    my $flags = detect_numeric(\@rows, 1, undef);
    ok(!$flags->[0], 'text column is not numeric');
};

subtest 'detect_numeric --- mixed column (one non-numeric --- text)' => sub {
    my @rows = (['1'], ['2'], ['three'], ['4']);
    my $flags = detect_numeric(\@rows, 1, undef);
    ok(!$flags->[0], 'column with any non-numeric value is text');
};

subtest 'detect_numeric --- empty values skipped' => sub {
    my @rows = (['1'], [''], ['3']);
    my $flags = detect_numeric(\@rows, 1, undef);
    ok($flags->[0], 'empty values do not disqualify a numeric column');
};

subtest 'detect_numeric --- limit respected' => sub {
    my @rows = (['1'], ['2'], ['three']);  # "three" at row index 2
    my $flags_limited = detect_numeric(\@rows, 1, 2);   # only sees rows 0+1
    my $flags_all     = detect_numeric(\@rows, 1, undef);

    ok($flags_limited->[0],  'limit=2: only sees numeric rows, column is numeric');
    ok(!$flags_all->[0],     'no limit: sees "three", column is text');
};

# ------------------------------
# build_row_line()
# ------------------------------
subtest 'build_row_line' => sub {
    my $fields     = ['Alice', '30', '98.5'];
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];

    my $line = build_row_line($fields, $col_widths, $is_numeric);
    is($line, 'Alice  30    98.5', 'text left-aligned, numerics right-aligned, joined with space');
    is(length($line), 5 + 1 + 3 + 1 + 7, 'total length = sum of widths + separators');
};

subtest 'build_row_line --- ragged row (missing fields --- empty)' => sub {
    my $fields     = ['Alice'];             # only 1 of 3 fields present
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];

    my $line = build_row_line($fields, $col_widths, $is_numeric);
    # col 0: 'Alice' left=5, col 1: '' right=3 spaces, col 2: '' right=7 spaces
    # total = 5 + 1 + 3 + 1 + 7 = 17 chars
    is($line, 'Alice            ', 'missing fields render as padded spaces');
};

# ------------------------------
# build_colnum_line()
# ------------------------------
subtest 'build_colnum_line' => sub {
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];
    my $line = build_colnum_line($col_widths, $is_numeric);
    # col 0 (text): "1    ", col 1 (numeric): "  2", col 2 (numeric): "      3"
    is($line, '1       2       3', 'column numbers follow column alignment (text left, numeric right)');
};

subtest 'build_colnum_line --- double-digit numbers' => sub {
    my $col_widths = [(3) x 10];
    my $is_numeric = [(1) x 10];
    my $line = build_colnum_line($col_widths, $is_numeric);
    like($line, qr/^\s*1\s+2\s+.*\s+10$/, 'numbers 1-10 all present');
};

subtest 'build_colnum_line --- 0-based indexing' => sub {
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];
    my $line = build_colnum_line($col_widths, $is_numeric, 0);
    is($line, '0       1       2', '0-based column numbers start at 0');
};

# ------------------------------
# total_line_width()
# ------------------------------
subtest 'total_line_width' => sub {
    is(total_line_width([5, 3, 7]), 5 + 1 + 3 + 1 + 7, '3 cols: widths + 2 separators');
    is(total_line_width([10]),      10,                  'single col: width only');
    is(total_line_width([]),        0,                   'no cols: 0');
};

# ------------------------------
# Fixture-based integration of pure functions
# ------------------------------
subtest 'fixture: basic.tsv --- column widths and numeric detection' => sub {
    my $fixture = "$Bin/fixtures/basic.tsv";
    open(my $fh, '<', $fixture) or die "Cannot open $fixture: $!";
    my @all_rows;
    while (<$fh>) {
        chomp;
        push @all_rows, [split /\t/, $_, -1];
    }
    close $fh;

    my $header  = $all_rows[0];
    my @data    = @all_rows[1..$#all_rows];
    my $n_cols  = scalar @$header;

    my $widths  = compute_col_widths(\@data, $header, $n_cols, undef);
    my $numeric = detect_numeric(\@data, $n_cols, undef);

    is($widths->[0], 5,  'col 0 (name): max width is 5 (Carol/Frank/Grace)');
    is($widths->[1], 3,  'col 1 (age): header "age" = 3');
    ok(!$numeric->[0],   'col 0 (name) is text');
    ok($numeric->[1],    'col 1 (age) is numeric');
    ok($numeric->[2],    'col 2 (score) is numeric');
    ok(!$numeric->[3],   'col 3 (city) is text');
    ok($numeric->[4],    'col 4 (is_active) is numeric');
};

subtest 'fixture: ragged.tsv --- handles missing fields' => sub {
    my $fixture = "$Bin/fixtures/ragged.tsv";
    open(my $fh, '<', $fixture) or die "Cannot open $fixture: $!";
    my @all_rows;
    while (<$fh>) {
        chomp;
        push @all_rows, [split /\t/, $_, -1];
    }
    close $fh;

    my $header = $all_rows[0];
    my @data   = @all_rows[1..$#all_rows];

    # n_cols is max across all rows
    my $n_cols = scalar @$header;
    for my $r (@data) { $n_cols = scalar(@$r) if scalar(@$r) > $n_cols; }

    my $widths = compute_col_widths(\@data, $header, $n_cols, undef);
    ok($n_cols >= 4, 'ragged file has at least 4 columns (from widest row)');
    ok($widths->[$_] > 0, "col $_ has positive width") for 0..$n_cols-1;

    # Render a short row without dying
    my $short_row = $data[2]; # gamma row has only 2 fields
    my @fields = map { $short_row->[$_] // '' } (0..$n_cols-1);
    my $is_numeric = detect_numeric(\@data, $n_cols, undef);
    my $line = build_row_line(\@fields, $widths, $is_numeric);
    ok(defined $line, 'render_row does not die on ragged row');
    is(length($line), total_line_width($widths), 'rendered line has correct total width');
};

subtest 'fixture: quoted.csv --- RFC 4180 parsing with widths and types' => sub {
    my $fixture = "$Bin/fixtures/quoted.csv";
    open(my $fh, '<', $fixture) or die "Cannot open $fixture: $!";
    my @all_rows;
    while (my $line = <$fh>) {
        push @all_rows, parse_csv_line($line, sub { scalar <$fh> });
    }
    close $fh;

    is(scalar @all_rows, 5, '5 rows total (1 header + 4 data rows)');
    is_deeply($all_rows[0], ['id', 'name', 'desc', 'price'], 'header unquoted');
    is_deeply($all_rows[1], ['1', 'Widget, Basic', 'Standard widget', '9.99'], 'row 1 commas preserved');
    is_deeply($all_rows[2], ['2', 'Widget "Pro"', 'Top widget "plus"', '29.99'], 'row 2 quotes unescaped');
    is_deeply($all_rows[3], ['3', 'Gadget', "Multi-line\\ngadget", '49.50'], 'row 3 multi-line field has \\n');

    my $header = $all_rows[0];
    my @data   = @all_rows[1..$#all_rows];
    my $n_cols = scalar @$header;
    my $widths = compute_col_widths(\@data, $header, $n_cols, undef);
    my $numeric = detect_numeric(\@data, $n_cols, undef);

    ok($numeric->[0], 'col 0 (id) is numeric');
    ok(!$numeric->[1], 'col 1 (name) is text');
    ok(!$numeric->[2], 'col 2 (desc) is text');
    ok($numeric->[3], 'col 3 (price) is numeric');
};

subtest 'format_line_num' => sub {
    is(format_line_num(0, 10),  ' 1 ', 'row 0 of 10 is " 1 "');
    is(format_line_num(9, 10),  '10 ', 'row 9 of 10 is "10 "');
    is(format_line_num(0, 100), '  1 ', 'row 0 of 100 is "  1 "');
    is(format_line_num(undef, 10), '   ', 'undef row is 3 spaces');
};

subtest 'format_option_prompt' => sub {
    my $off_prompt = format_option_prompt(0, 80);
    like($off_prompt, qr/\e\[7;33m/, 'uses reverse yellow ANSI escape code');
    like(strip_ansi($off_prompt), qr/^Constantly display line numbers  \(press RETURN\)\s*$/, 'message when line numbers off');
    is(length(strip_ansi($off_prompt)), 80, 'padded to term_cols width');

    my $on_prompt = format_option_prompt(1, 80);
    like($on_prompt, qr/\e\[7;33m/, 'uses reverse yellow ANSI escape code');
    like(strip_ansi($on_prompt), qr/^Don't use line numbers  \(press RETURN\)\s*$/, 'message when line numbers on');
    is(length(strip_ansi($on_prompt)), 80, 'padded to term_cols width');
};

subtest 'find_matches' => sub {
    my @rows = (
        ['Alice', '30', '98.5'],
        ['Bob',   '250', '7'],
        ['Carol', '42', '88.3333'],
    );
    my $regex = qr/a/i;
    my $matches = find_matches(\@rows, 3, $regex);
    is_deeply($matches, [ [0, 0], [2, 0] ], 'finds case-insensitive matching cells');

    # Multi-field match across tab delimiter
    my $multi_match = find_matches(\@rows, 3, qr/Alice\t30/);
    is_deeply($multi_match, [ [0, 0] ], 'matches across tab delimiter, starting at col 0');

    # Multi-field match starting in col 1 across delimiter
    my $multi_match2 = find_matches(\@rows, 3, qr/30\t98\.5/);
    is_deeply($multi_match2, [ [0, 1] ], 'matches starting in col 1 across delimiter');

    # Custom delimiter
    my $csv_rows = [ ['Alice', '30'], ['Bob', '25'] ];
    my $csv_matches = find_matches($csv_rows, 2, qr/Alice,30/, ',');
    is_deeply($csv_matches, [ [0, 0] ], 'matches multi-field pattern with custom delimiter');

    # Deduplication per row
    my $dup_rows = [ ['cat', 'cat', 'dog'] ];
    my $dup_matches = find_matches($dup_rows, 3, qr/cat/);
    is_deeply($dup_matches, [ [0, 0], [0, 1] ], 'finds matches in col 0 and col 1');

    my $dup_rows_same_col = [ ['cat cat', 'dog'] ];
    my $dup_same_col = find_matches($dup_rows_same_col, 2, qr/cat/);
    is_deeply($dup_same_col, [ [0, 0] ], 'deduplicates multiple matches in the same cell');
};

subtest 'filter_rows' => sub {
    my @rows = (
        ['Alice', '30', 'New York'],
        ['Bob',   '25', 'Los Angeles'],
        ['Carol', '42', 'Chicago'],
    );

    my $all = filter_rows(\@rows, undef);
    is_deeply($all, [0, 1, 2], 'undef regex returns all row indices');

    my $filtered = filter_rows(\@rows, qr/Alice/);
    is_deeply($filtered, [0], 'filters rows matching regex');

    my $city_match = filter_rows(\@rows, qr/Chicago/);
    is_deeply($city_match, [2], 'filters rows matching cell in another column');

    my $nomatch = filter_rows(\@rows, qr/NonExistent/);
    is_deeply($nomatch, [], 'no match returns empty arrayref');

    # Multi-field regex match across tab delimiter
    my $multi_filter = filter_rows(\@rows, qr/Alice\t30/);
    is_deeply($multi_filter, [0], 'filters rows matching across column boundary');

    # Custom delimiter filter
    my $csv_rows = [ ['Alice', '30'], ['Bob', '25'] ];
    my $csv_filter = filter_rows($csv_rows, qr/Bob,25/, ',');
    is_deeply($csv_filter, [1], 'filters rows matching custom delimiter');
};

subtest 'render_clipped_row --- multi-field match highlighting' => sub {
    my $fields     = ['Alice', '30', '98.5'];
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];

    # Multi-field match regex: qr/Alice\t30/
    # Active match target is [0, 0]
    # Cell 0 (Alice) overlaps match and is active -> \e[42;30m
    # Cell 1 (30) overlaps match and is non-active -> \e[32m
    # Cell 2 (98.5) does not overlap -> no ANSI codes
    my $rendered = render_clipped_row($fields, $col_widths, $is_numeric, 0, 30, 0, qr/Alice\t30/, [0, 0], "\t");
    like($rendered, qr/\e\[42;30mAlice\e\[0m/, 'active col 0 has black on green bg');
    like($rendered, qr/\e\[32m 30\e\[0m/, 'overlapping col 1 has green text');
    unlike($rendered, qr/98\.5.*\e\[/, 'non-overlapping col 2 is not highlighted');
};

subtest 'find_next_match_index --- forward navigation & wrap' => sub {
    my $matches = [ [0, 1], [1, 1], [2, 1] ];

    # From (-1, -1) or start, next is (0, 1) -> index 0
    my ($idx1, $wrap1) = find_next_match_index($matches, -1, -1, 1);
    is($idx1, 0, 'finds first match after start');
    is($wrap1, 0, 'not wrapped');

    # From (0, 1), next is (1, 1) -> index 1
    my ($idx2, $wrap2) = find_next_match_index($matches, 0, 1, 1);
    is($idx2, 1, 'finds next match after (0,1)');
    is($wrap2, 0, 'not wrapped');

    # From (2, 1), next wraps to (0, 1) -> index 0
    my ($idx3, $wrap3) = find_next_match_index($matches, 2, 1, 1);
    is($idx3, 0, 'wraps forward to first match');
    is($wrap3, 1, 'wrapped flag set');
};

subtest 'find_next_match_index --- backward navigation & wrap' => sub {
    my $matches = [ [0, 1], [1, 1], [2, 1] ];

    # From (2, 1), prev is (1, 1) -> index 1
    my ($idx1, $wrap1) = find_next_match_index($matches, 2, 1, -1);
    is($idx1, 1, 'finds previous match before (2,1)');
    is($wrap1, 0, 'not wrapped');

    # From (0, 1), prev wraps to (2, 1) -> index 2
    my ($idx2, $wrap2) = find_next_match_index($matches, 0, 1, -1);
    is($idx2, 2, 'wraps backward to last match');
    is($wrap2, 1, 'wrapped flag set');
};

subtest 'render_clipped_row' => sub {
    my $fields     = ['Alice', '30', '98.5'];
    my $col_widths = [5, 3, 7];
    my $is_numeric = [0, 1, 1];

    # Without search: matches clip_content(build_row_line(...))
    my $plain = render_clipped_row($fields, $col_widths, $is_numeric, 0, 20, 0, undef, undef);
    is($plain, 'Alice  30    98.5   ', 'plain clipped row matches expected spacing');

    # With search: cell 0 matching and active
    my $active = render_clipped_row($fields, $col_widths, $is_numeric, 0, 20, 0, qr/Alice/, [0, 0]);
    like($active, qr/\e\[42;30mAlice\e\[0m/, 'active match highlighted in black on green bg');

    # With search: cell 0 matching but not active
    my $match = render_clipped_row($fields, $col_widths, $is_numeric, 0, 20, 0, qr/Alice/, [1, 0]);
    like($match, qr/\e\[32mAlice\e\[0m/, 'other match highlighted in green text');
};

subtest 'compute_search_h_offset' => sub {
    is(compute_search_h_offset(0, 10, 80, 200), 0, 'entire field visible at offset 0 returns 0');
    is(compute_search_h_offset(5, 10, 80, 200), 0, 'field ending before content_w returns 0 offset');
    is(compute_search_h_offset(100, 20, 80, 200), 70, 'centers field in viewport when not visible at offset 0');
    is(compute_search_h_offset(200, 20, 80, 100), 100, 'clamps target offset to max_h');
};

# ------------------------------
# History & ReadLine-style Prompt Editing Tests
# ------------------------------

subtest 'add_to_history' => sub {
    my $hist = [];
    add_to_history($hist, 'first', 100);
    is_deeply($hist, ['first'], 'adds first entry');

    add_to_history($hist, 'second', 100);
    is_deeply($hist, ['first', 'second'], 'adds second entry');

    # Ignore empty or undef
    add_to_history($hist, '', 100);
    add_to_history($hist, undef, 100);
    is_deeply($hist, ['first', 'second'], 'ignores empty and undef entries');

    # Move existing entry to end
    add_to_history($hist, 'first', 100);
    is_deeply($hist, ['second', 'first'], 'moves duplicate to end');

    # Consecutive duplicate
    add_to_history($hist, 'first', 100);
    is_deeply($hist, ['second', 'first'], 'consecutive duplicate not duplicated');

    # Truncation at max_size
    my $small_hist = ['a', 'b', 'c'];
    add_to_history($small_hist, 'd', 3);
    is_deeply($small_hist, ['b', 'c', 'd'], 'truncates oldest when exceeding max_size');
};

subtest 'load_history_file & save_history_file' => sub {
    require File::Temp;
    my $temp_file = File::Temp->new(UNLINK => 1)->filename;

    # Missing file returns empty arrays
    my ($search_h, $filter_h) = load_history_file('/path/to/nonexistent/dless_history_test');
    is_deeply($search_h, [], 'search history empty for missing file');
    is_deeply($filter_h, [], 'filter history empty for missing file');

    # Save histories
    my $s_in = ['pattern1', 'pattern2'];
    my $f_in = ['filter1', 'filter2'];
    save_history_file($temp_file, $s_in, $f_in, 100);

    # Load back
    my ($s_out, $f_out) = load_history_file($temp_file);
    is_deeply($s_out, ['pattern1', 'pattern2'], 'search history loaded correctly');
    is_deeply($f_out, ['filter1', 'filter2'], 'filter history loaded correctly');

    # Truncation on save
    my @many_s = map { "s$_" } (1 .. 120);
    my @many_f = map { "f$_" } (1 .. 120);
    save_history_file($temp_file, \@many_s, \@many_f, 100);
    my ($s_trunc, $f_trunc) = load_history_file($temp_file);
    is(scalar(@$s_trunc), 100, 'search history capped at 100 on save');
    is(scalar(@$f_trunc), 100, 'filter history capped at 100 on save');
    is($s_trunc->[0], 's21', 'oldest search entries truncated');
    is($s_trunc->[-1], 's120', 'newest search entry preserved');
};

subtest 'prompt_edit_step --- basic typing & cursor' => sub {
    my $state = {
        buffer   => '',
        cursor   => 0,
        history  => ['foo', 'bar'],
        hist_idx => undef,
        draft    => '',
    };

    # Type 'a', 'b', 'c'
    prompt_edit_step($state, 'a');
    prompt_edit_step($state, 'b');
    prompt_edit_step($state, 'c');
    is($state->{buffer}, 'abc', 'typed abc');
    is($state->{cursor}, 3, 'cursor at end');

    # Cursor left
    prompt_edit_step($state, "\e[D");
    is($state->{cursor}, 2, 'cursor moved left');
    prompt_edit_step($state, "\x02"); # Ctrl-B
    is($state->{cursor}, 1, 'cursor moved left with Ctrl-B');

    # Insert 'X' at cursor 1 -> 'aXbc'
    prompt_edit_step($state, 'X');
    is($state->{buffer}, 'aXbc', 'inserted char at cursor');
    is($state->{cursor}, 2, 'cursor advanced');

    # Cursor right
    prompt_edit_step($state, "\e[C");
    is($state->{cursor}, 3, 'cursor moved right');
    prompt_edit_step($state, "\x06"); # Ctrl-F
    is($state->{cursor}, 4, 'cursor moved right with Ctrl-F');

    # Home / End / Ctrl-A / Ctrl-E
    prompt_edit_step($state, "\x01"); # Ctrl-A
    is($state->{cursor}, 0, 'cursor at start with Ctrl-A');
    prompt_edit_step($state, "\x05"); # Ctrl-E
    is($state->{cursor}, 4, 'cursor at end with Ctrl-E');
    prompt_edit_step($state, "\e[H"); # Home
    is($state->{cursor}, 0, 'cursor at start with Home');
    prompt_edit_step($state, "\e[F"); # End
    is($state->{cursor}, 4, 'cursor at end with End');
};

subtest 'prompt_edit_step --- backspace and delete' => sub {
    my $state = {
        buffer   => 'abcd',
        cursor   => 2,
        history  => [],
        hist_idx => undef,
        draft    => '',
    };

    # Backspace at cursor 2 ('ab|cd') -> deletes 'b' -> 'acd', cursor 1
    prompt_edit_step($state, "\x7f");
    is($state->{buffer}, 'acd', 'backspace deleted preceding char');
    is($state->{cursor}, 1, 'cursor moved left');

    # Delete at cursor 1 ('a|cd') -> deletes 'c' -> 'ad', cursor 1
    prompt_edit_step($state, "\e[3~");
    is($state->{buffer}, 'ad', 'delete deleted char under cursor');
    is($state->{cursor}, 1, 'cursor remained at 1');

    # Ctrl-D at cursor 1 ('a|d') -> deletes 'd' -> 'a', cursor 1
    prompt_edit_step($state, "\x04");
    is($state->{buffer}, 'a', 'Ctrl-D deleted char under cursor');
    is($state->{cursor}, 1, 'cursor at 1');

    # Delete at end of buffer does nothing
    prompt_edit_step($state, "\e[3~");
    is($state->{buffer}, 'a', 'Delete at end is no-op');

    # Backspace at start of buffer does nothing
    $state->{cursor} = 0;
    prompt_edit_step($state, "\x7f");
    is($state->{buffer}, 'a', 'Backspace at start is no-op');
};

subtest 'prompt_edit_step --- kill and word navigation (ReadLine emulation)' => sub {
    my $state = {
        buffer   => 'hello world again',
        cursor   => 5, # 'hello| world again'
        history  => [],
        hist_idx => undef,
        draft    => '',
    };

    # Ctrl-K (kill to end)
    prompt_edit_step($state, "\x0b");
    is($state->{buffer}, 'hello', 'Ctrl-K killed to end of line');
    is($state->{cursor}, 5, 'cursor remains at 5');

    # Type more
    prompt_edit_step($state, ' brave new world');
    is($state->{buffer}, 'hello brave new world', 'appended text');

    # Ctrl-W (backward kill word)
    prompt_edit_step($state, "\x17");
    is($state->{buffer}, 'hello brave new ', 'Ctrl-W killed word');

    # Ctrl-U (kill entire line / kill to beginning)
    prompt_edit_step($state, "\x15");
    is($state->{buffer}, '', 'Ctrl-U cleared line');
    is($state->{cursor}, 0, 'cursor reset to 0');

    # Word navigation (Alt-b, Alt-f)
    $state->{buffer} = 'one two three';
    $state->{cursor} = 13;
    prompt_edit_step($state, "\eb"); # Alt-B
    is($state->{cursor}, 8, 'Alt-B moved back one word (to "three")');
    prompt_edit_step($state, "\eb");
    is($state->{cursor}, 4, 'Alt-B moved back another word (to "two")');
    prompt_edit_step($state, "\ef"); # Alt-F
    is($state->{cursor}, 7, 'Alt-F moved forward one word');
};

subtest 'prompt_edit_step --- history navigation (Up / Down)' => sub {
    my $state = {
        buffer   => 'my_draft',
        cursor   => 8,
        history  => ['first_regex', 'second_regex', 'third_regex'],
        hist_idx => undef,
        draft    => '',
    };

    # Up Arrow -> loads newest history entry ('third_regex')
    prompt_edit_step($state, "\e[A");
    is($state->{buffer}, 'third_regex', 'Up recalls newest history item');
    is($state->{cursor}, length('third_regex'), 'cursor placed at end of recalled text');
    is($state->{draft}, 'my_draft', 'draft saved');
    is($state->{hist_idx}, 2, 'history index at 2');

    # Up Arrow again -> loads 'second_regex'
    prompt_edit_step($state, "\e[A");
    is($state->{buffer}, 'second_regex', 'Up recalls previous history item');
    is($state->{hist_idx}, 1, 'history index at 1');

    # Up Arrow again -> loads 'first_regex'
    prompt_edit_step($state, "\e[A");
    is($state->{buffer}, 'first_regex', 'Up recalls oldest history item');
    is($state->{hist_idx}, 0, 'history index at 0');

    # Up Arrow at oldest -> stays at 'first_regex'
    prompt_edit_step($state, "\e[A");
    is($state->{buffer}, 'first_regex', 'Up at oldest stays at oldest');
    is($state->{hist_idx}, 0, 'history index remains 0');

    # Down Arrow -> loads 'second_regex'
    prompt_edit_step($state, "\e[B");
    is($state->{buffer}, 'second_regex', 'Down moves forward to second_regex');
    is($state->{hist_idx}, 1, 'history index at 1');

    # Down Arrow -> loads 'third_regex'
    prompt_edit_step($state, "\e[B");
    is($state->{buffer}, 'third_regex', 'Down moves forward to third_regex');
    is($state->{hist_idx}, 2, 'history index at 2');

    # Down Arrow past newest -> restores draft
    prompt_edit_step($state, "\e[B");
    is($state->{buffer}, 'my_draft', 'Down past newest restores uncommitted draft');
    is($state->{cursor}, length('my_draft'), 'cursor at end of draft');
    is($state->{hist_idx}, undef, 'history index reset to undef');

    # Down Arrow when already at draft is no-op
    prompt_edit_step($state, "\e[B");
    is($state->{buffer}, 'my_draft', 'Down when at draft remains at draft');
};

# ------------------------------
# parse_csv_line Tests
# ------------------------------

subtest 'parse_csv_line --- simple unquoted' => sub {
    my $fields = parse_csv_line('foo,bar,baz');
    is_deeply($fields, ['foo', 'bar', 'baz'], 'parses simple unquoted fields');
};

subtest 'parse_csv_line --- quoted fields with commas' => sub {
    my $fields = parse_csv_line('1,"Widget, Basic","A standard, everyday widget",9.99');
    is_deeply($fields, ['1', 'Widget, Basic', 'A standard, everyday widget', '9.99'], 'removes quotes and preserves embedded commas');
};

subtest 'parse_csv_line --- escaped quotes' => sub {
    my $fields = parse_csv_line('2,"Widget ""Pro""","Top-tier widget with ""extra"" features",29.99');
    is_deeply($fields, ['2', 'Widget "Pro"', 'Top-tier widget with "extra" features', '29.99'], 'unescapes doubled double quotes to single quote');
};

subtest 'parse_csv_line --- embedded newlines' => sub {
    my @lines = ("gadget description\",49.50");
    my $fields = parse_csv_line("3,Gadget,\"Multi-line\n", sub { shift @lines });
    is_deeply($fields, ['3', 'Gadget', 'Multi-line\ngadget description', '49.50'], 'replaces embedded newline with literal \n');
};

subtest 'parse_csv_line --- empty and trailing fields' => sub {
    my $fields1 = parse_csv_line('a,"",c');
    is_deeply($fields1, ['a', '', 'c'], 'handles empty quoted field');

    my $fields2 = parse_csv_line('a,,c');
    is_deeply($fields2, ['a', '', 'c'], 'handles empty unquoted field');

    my $fields3 = parse_csv_line('a,b,');
    is_deeply($fields3, ['a', 'b', ''], 'handles trailing comma');

    my $fields4 = parse_csv_line('');
    is_deeply($fields4, [''], 'empty line returns single empty field');
};

subtest 'parse_csv_line --- unclosed quote at EOF' => sub {
    my $fields = parse_csv_line('1,"Unclosed quote field', sub { undef });
    is_deeply($fields, ['1', 'Unclosed quote field'], 'gracefully handles unclosed quote at EOF without crashing');
};

# ------------------------------
# adjust_column_widths & hidden column rendering Tests
# ------------------------------

subtest 'adjust_column_widths --- empty toggles all columns' => sub {
    my $orig   = [10, 20, 30];
    my $curr   = [5, 1, 10];
    my $hidden = [0, 1, 0];
    my $header = ['name', 'age', 'score'];

    # 1. When not at full width, empty input restores all columns
    my ($ok1, $msg1) = adjust_column_widths($orig, $curr, $hidden, $header, '', 3);
    ok($ok1, 'empty input succeeds when restoring');
    is_deeply($curr, [10, 20, 30], 'all column widths restored');
    is_deeply($hidden, [0, 0, 0], 'all hidden flags cleared');
    like($msg1, qr/Reset all columns to original widths/i, 'restore message returned');

    # 2. When all columns are at full width, empty input shrinks all to header width
    my ($ok2, $msg2) = adjust_column_widths($orig, $curr, $hidden, $header, '', 3);
    ok($ok2, 'empty input succeeds when shrinking all to header');
    is_deeply($curr, [4, 3, 5], 'all column widths shrunk to header length');
    is_deeply($hidden, [0, 0, 0], 'hidden flags remain cleared');
    like($msg2, qr/Shrunk all columns to header width/i, 'shrink message returned');

    # 3. Subsequent empty input restores back to full width
    my ($ok3, $msg3) = adjust_column_widths($orig, $curr, $hidden, $header, '', 3);
    ok($ok3, 'subsequent empty input succeeds');
    is_deeply($curr, [10, 20, 30], 'all column widths restored to full width');
    is_deeply($hidden, [0, 0, 0], 'hidden flags cleared');
    like($msg3, qr/Reset all columns to original widths/i, 'restore message returned');

    # 4. Header with empty string gets minimum width 1
    my $empty_h = ['', 'a', 'xyz'];
    my $curr_h  = [10, 10, 10];
    my $orig_h  = [10, 10, 10];
    my $hid_h   = [0, 0, 0];
    adjust_column_widths($orig_h, $curr_h, $hid_h, $empty_h, '', 3);
    is_deeply($curr_h, [1, 1, 3], 'empty header column gets minimum width 1');
};

subtest 'adjust_column_widths --- shrink to header length and toggle' => sub {
    my $orig   = [10, 20, 30];
    my $curr   = [10, 20, 30];
    my $hidden = [0, 0, 0];
    my $header = ['colname', 'a', 'very_long_header_name'];

    # Shrink column 1 (header 'colname' = 7 chars)
    my ($ok1) = adjust_column_widths($orig, $curr, $hidden, $header, '1', 3);
    ok($ok1, 'col 1 shrunk');
    is($curr->[0], 7, 'col 1 width is 7 (length of header)');

    # Toggle column 1 back to original width
    my ($ok2) = adjust_column_widths($orig, $curr, $hidden, $header, '1', 3);
    ok($ok2, 'col 1 toggled');
    is($curr->[0], 10, 'col 1 width restored to 10');

    # Header shorter than 1 char defaults to min 1
    my $empty_header = ['', '', ''];
    adjust_column_widths($orig, $curr, $hidden, $empty_header, '1', 3);
    is($curr->[0], 1, 'empty header shrinks to min width 1');
};

subtest 'adjust_column_widths --- custom width' => sub {
    my $orig   = [10, 20, 30];
    my $curr   = [10, 20, 30];
    my $hidden = [0, 0, 0];
    my $header = ['col1', 'col2', 'col3'];

    my ($ok) = adjust_column_widths($orig, $curr, $hidden, $header, '2:15', 3);
    ok($ok, 'col 2 custom width set');
    is($curr->[1], 15, 'col 2 width is 15');
    is($hidden->[1], 0, 'col 2 not hidden');

    # Toggle column 2 with just '2' restores original
    adjust_column_widths($orig, $curr, $hidden, $header, '2', 3);
    is($curr->[1], 20, 'col 2 restored to original width 20');
};

subtest 'adjust_column_widths --- hide column with :0' => sub {
    my $orig   = [10, 20, 30];
    my $curr   = [10, 20, 30];
    my $hidden = [0, 0, 0];
    my $header = ['col1', 'col2', 'col3'];

    my ($ok) = adjust_column_widths($orig, $curr, $hidden, $header, '3:0', 3);
    ok($ok, 'col 3 hidden');
    is($curr->[2], 1, 'col 3 width set to 1 for |');
    is($hidden->[2], 1, 'col 3 hidden flag set');

    # Toggle column 3 with '3' restores original
    adjust_column_widths($orig, $curr, $hidden, $header, '3', 3);
    is($curr->[2], 30, 'col 3 restored to original width 30');
    is($hidden->[2], 0, 'col 3 hidden flag cleared');
};

subtest 'adjust_column_widths --- hide column with N- synonym' => sub {
    my $orig   = [10, 20, 30];
    my $curr   = [10, 20, 30];
    my $hidden = [0, 0, 0];
    my $header = ['col1', 'col2', 'col3'];

    # Hide col 3 with 3-
    my ($ok, $msg) = adjust_column_widths($orig, $curr, $hidden, $header, '3-', 3);
    ok($ok, 'col 3 hidden with 3-');
    is($curr->[2], 1, 'col 3 width set to 1 for |');
    is($hidden->[2], 1, 'col 3 hidden flag set');

    # Idempotent: hiding again keeps it hidden
    my ($ok_idempotent) = adjust_column_widths($orig, $curr, $hidden, $header, '3-', 3);
    ok($ok_idempotent, 'col 3 remains hidden on repeated 3-');
    is($curr->[2], 1, 'col 3 width remains 1');
    is($hidden->[2], 1, 'col 3 hidden flag remains 1');

    # Toggle column 3 with '3' restores original
    adjust_column_widths($orig, $curr, $hidden, $header, '3', 3);
    is($curr->[2], 30, 'col 3 restored to original width 30');
    is($hidden->[2], 0, 'col 3 hidden flag cleared');

    # Multi-token with N- (e.g. '1- 2:15 3-')
    my $curr_m   = [10, 20, 30];
    my $hidden_m = [0, 0, 0];
    my ($ok_multi) = adjust_column_widths($orig, $curr_m, $hidden_m, $header, '1- 2:15 3-', 3);
    ok($ok_multi, 'multiple specifiers with N- succeeded');
    is($curr_m->[0], 1, 'col 1 hidden with 1-');
    is($hidden_m->[0], 1, 'col 1 hidden flag set');
    is($curr_m->[1], 15, 'col 2 set to width 15');
    is($hidden_m->[1], 0, 'col 2 hidden flag 0');
    is($curr_m->[2], 1, 'col 3 hidden with 3-');
    is($hidden_m->[2], 1, 'col 3 hidden flag set');

    # Out of bounds with dash
    my ($ok_oob, $err_oob) = adjust_column_widths($orig, $curr, $hidden, $header, '4-', 3);
    ok(!$ok_oob, 'col 4- out of bounds fails');
    is($err_oob, 'Invalid column number: 4', 'expected error message for out of bounds col');

    my ($ok_zero, $err_zero) = adjust_column_widths($orig, $curr, $hidden, $header, '0-', 3);
    ok(!$ok_zero, 'col 0- fails (1-based)');
    is($err_zero, 'Invalid column number: 0', 'expected error message for col 0-');

    # Malformed dash syntax
    my ($ok_bad, $err_bad) = adjust_column_widths($orig, $curr, $hidden, $header, '-1', 3);
    ok(!$ok_bad, '-1 fails');
    is($err_bad, 'Invalid column width specification: -1', 'expected error message for -1');
};

subtest 'adjust_column_widths --- multiple specifiers on one line' => sub {
    my $orig   = [10, 20, 30, 40];
    my $curr   = [10, 20, 30, 40];
    my $hidden = [0, 0, 0, 0];
    my $header = ['name', 'age', 'score', 'city'];

    # Multiple specifiers: '1 2:15 3:0' -> shrink col 1, set col 2 to 15, hide col 3
    my ($ok, $msg) = adjust_column_widths($orig, $curr, $hidden, $header, '1 2:15 3:0', 4);
    ok($ok, 'multiple specifiers succeeded');
    is($curr->[0], 4, 'col 1 shrunk to header length (name=4)');
    is($curr->[1], 15, 'col 2 set to 15');
    is($curr->[2], 1, 'col 3 set to 1 (hidden)');
    is($hidden->[2], 1, 'col 3 hidden flag set');
    is($curr->[3], 40, 'col 4 untouched');

    # Multiple specifiers with invalid token: all-or-nothing check
    my ($fail_ok, $fail_msg) = adjust_column_widths($orig, $curr, $hidden, $header, '1 5:10', 4);
    ok(!$fail_ok, 'fails when any token is out of bounds');
};

subtest 'adjust_column_widths --- error handling' => sub {
    my $orig   = [10, 20];
    my $curr   = [10, 20];
    my $hidden = [0, 0];
    my $header = ['col1', 'col2'];

    my ($ok1, $err1) = adjust_column_widths($orig, $curr, $hidden, $header, '3', 2);
    ok(!$ok1, 'col 3 out of bounds fails');

    my ($ok2, $err2) = adjust_column_widths($orig, $curr, $hidden, $header, '0', 2);
    ok(!$ok2, 'col 0 fails (1-based)');

    my ($ok3, $err3) = adjust_column_widths($orig, $curr, $hidden, $header, 'invalid', 2);
    ok(!$ok3, 'invalid text fails');
};

subtest 'hidden column rendering in lines' => sub {
    my $col_widths = [5, 1, 6];
    my $is_numeric = [0, 0, 1];
    my $is_hidden  = [0, 1, 0];

    my $colnum_line = build_colnum_line($col_widths, $is_numeric, 1, $is_hidden);
    is($colnum_line, "1     |      3", 'hidden column rendered as | in colnum line');

    my $header_line = build_row_line(['name', 'secret', 'score'], $col_widths, $is_numeric, $is_hidden);
    is($header_line, "name  |  score", 'hidden column rendered as | in header line');

    my $row_line = render_clipped_row(
        ['Alice', 'hidden_data', '99.5'],
        $col_widths, $is_numeric,
        0, 20, 0, undef, undef, "\t", $is_hidden
    );
    is($row_line, "Alice |   99.5      ", 'hidden column rendered as | in data row');
};

subtest 'multiple adjacent hidden columns rendered without spaces' => sub {
    my $col_widths = [5, 1, 1, 1, 6];
    my $is_numeric = [0, 0, 0, 0, 1];
    my $is_hidden  = [0, 1, 1, 1, 0];

    my $colnum_line = build_colnum_line($col_widths, $is_numeric, 1, $is_hidden);
    is($colnum_line, "1     |||      5", 'adjacent hidden columns rendered as ||| without spaces in colnum line');

    my $header_line = build_row_line(['name', 'c2', 'c3', 'c4', 'score'], $col_widths, $is_numeric, $is_hidden);
    is($header_line, "name  |||  score", 'adjacent hidden columns rendered as ||| without spaces in header line');

    my $row_line = render_clipped_row(
        ['Alice', 'd2', 'd3', 'd4', '99.5'],
        $col_widths, $is_numeric,
        0, 20, 0, undef, undef, "\t", $is_hidden
    );
    is($row_line, "Alice |||   99.5    ", 'adjacent hidden columns rendered as ||| without spaces in data row');

    is(total_line_width($col_widths, $is_hidden), 16, 'total_line_width excludes spaces between adjacent hidden columns');
};

subtest 'help box dimensions and format' => sub {
    # Verify that the help box lines in dless are uniform in width and under 24 lines tall
    open my $fh, '<', "$Bin/../dless" or die $!;
    my @help_lines;
    my $in_help = 0;
    while (my $line = <$fh>) {
        if ($line =~ /my \@lines = \(/) {
            $in_help = 1;
            next;
        }
        if ($in_help) {
            last if $line =~ /^\s*\);/;
            if ($line =~ /'([^']+)'/) {
                push @help_lines, $1;
            }
        }
    }
    close $fh;

    cmp_ok(scalar(@help_lines), '<=', 20, 'help box height is well under 24 lines (<= 20)');
    my $expected_w = length($help_lines[0]);
    for my $i (0 .. $#help_lines) {
        is(length($help_lines[$i]), $expected_w, "help line $i has uniform width $expected_w");
    }
};

subtest 'format_usage_message and format_detailed_help' => sub {
    my $usage = format_usage_message();
    like($usage, qr/Usage: dless/, 'usage contains usage line');
    like($usage, qr/--delimiter/, 'usage lists options');
    unlike($usage, qr/Navigation Commands:/, 'short usage does not contain full command list');

    my $help = format_detailed_help();
    like($help, qr/Usage: dless/, 'detailed help contains usage line');
    like($help, qr/Navigation Commands:/, 'detailed help contains navigation commands section');
    like($help, qr/Search & Filter Commands:/, 'detailed help contains search and filter commands section');
    like($help, qr/Column & Display Commands:/, 'detailed help contains column commands section');
    like($help, qr/Adjust column widths/, 'detailed help describes w command');
    like($help, qr/N:0,\s*N-/, 'detailed help lists N- synonym for hiding columns');
    like($help, qr/gzip|zstd/i, 'detailed help mentions automatic decompression');
};

subtest 'detect_compression pure function' => sub {
    # Magic bytes check
    is(detect_compression("\x1f\x8b\x08\x00"), 'gzip', 'detects gzip from magic bytes');
    is(detect_compression("\x28\xb5\x2f\xfd"), 'zstd', 'detects zstd from magic bytes');
    is(detect_compression("\x1f"), undef, 'incomplete 1-byte gzip magic returns undef');
    is(detect_compression("\x28\xb5\x2f"), undef, 'incomplete 3-byte zstd magic returns undef');
    is(detect_compression("\x00\x01\x02\x03"), undef, 'non-magic 4 bytes returns undef');

    # Filename extension fallback
    is(detect_compression("data", "data.tsv.gz"), 'gzip', 'detects gzip from .gz extension');
    is(detect_compression("data", "data.tsv.zst"), 'zstd', 'detects zstd from .zst extension');
    is(detect_compression("data", "data.tsv.zstd"), 'zstd', 'detects zstd from .zstd extension');

    # Uncompressed / plain text
    is(detect_compression("name\tage\n", "basic.tsv"), undef, 'plain text returns undef');
    is(detect_compression(""), undef, 'empty header returns undef');
    is(detect_compression(undef), undef, 'undef header returns undef');
};

subtest 'get_decompressor_command pure function' => sub {
    is_deeply([get_decompressor_command('gzip', 'foo.gz')], ['gzip', '-dc', '--', 'foo.gz'], 'gzip command with file');
    is_deeply([get_decompressor_command('gzip')], ['gzip', '-dc'], 'gzip command without file (stdin)');
    is_deeply([get_decompressor_command('zstd', 'foo.zst')], ['zstd', '-dc', '--', 'foo.zst'], 'zstd command with file');
    is_deeply([get_decompressor_command('zstd')], ['zstd', '-dc'], 'zstd command without file (stdin)');
};

subtest 'max_vertical_offset pure function' => sub {
    is(max_vertical_offset(0), 0, '0 rows returns 0');
    is(max_vertical_offset(1), 0, '1 row returns 0 (row 1 is top line)');
    is(max_vertical_offset(2), 1, '2 rows returns 1 (row 2 can be top line)');
    is(max_vertical_offset(10), 9, '10 rows returns 9 (row 10 can be top line)');
    is(max_vertical_offset(100), 99, '100 rows returns 99');
};

subtest 'bottom_vertical_offset pure function' => sub {
    is(bottom_vertical_offset(0, 20), 0, '0 rows with 20 viewport rows returns 0');
    is(bottom_vertical_offset(5, 20), 0, '5 rows with 20 viewport rows returns 0');
    is(bottom_vertical_offset(20, 20), 0, '20 rows with 20 viewport rows returns 0');
    is(bottom_vertical_offset(25, 20), 5, '25 rows with 20 viewport rows returns 5');
    is(bottom_vertical_offset(100, 20), 80, '100 rows with 20 viewport rows returns 80');
};

subtest 'start_search_status_msg pure function' => sub {
    is(start_search_status_msg('/', 'Alice'), 'Searching...', '/ with query returns Searching...');
    is(start_search_status_msg('/', ''), undef, '/ with empty query returns undef');
    is(start_search_status_msg('&', 'Alice'), 'Filtering...', '& with query returns Filtering...');
    is(start_search_status_msg('&', ''), undef, '& with empty query returns undef');
    is(start_search_status_msg('w', '1:10'), undef, 'w with query returns undef');
    is(start_search_status_msg(undef, 'Alice'), undef, 'undef mode returns undef');
};

subtest 'get_visible_column_indices pure function' => sub {
    my $col_widths = [10, 20, 15];
    my $is_hidden  = [0, 0, 0];

    # Viewport 0..24: Col 0 (0..9) and Col 1 (11..30) overlap
    my $vis1 = get_visible_column_indices($col_widths, $is_hidden, 0, 25);
    is_deeply($vis1, { 0 => 1, 1 => 1 }, 'cols 0 and 1 visible in 25-char viewport at offset 0');

    # Viewport 15..24: only Col 1 (11..30) overlaps
    my $vis2 = get_visible_column_indices($col_widths, $is_hidden, 15, 10);
    is_deeply($vis2, { 1 => 1 }, 'only col 1 visible at offset 15 with width 10');

    # Viewport 32..50: only Col 2 (32..46) overlaps
    my $vis3 = get_visible_column_indices($col_widths, $is_hidden, 32, 20);
    is_deeply($vis3, { 2 => 1 }, 'only col 2 visible at offset 32 with width 20');

    # Hidden columns without separators between adjacent hidden
    my $col_widths_h = [10, 1, 1, 10];
    my $is_hidden_h  = [0, 1, 1, 0];
    # Col 0: 0..9, Sep: 10, Col 1: 11..11, Col 2: 12..12, Sep: 13, Col 3: 14..23
    my $vis4 = get_visible_column_indices($col_widths_h, $is_hidden_h, 14, 5);
    is_deeply($vis4, { 3 => 1 }, 'col 3 correctly located after adjacent hidden columns');
};

subtest 'get_visible_field_max_widths pure function' => sub {
    my $data = [
        ['Alice', 'Engineering and Architecture', '99.5'],
        ['Bob',   'Sales',                         '72.0'],
        ['Carol', 'Human Resources Operations',    '88.3'],
    ];
    # Visible rows 0 and 1
    my $w1 = get_visible_field_max_widths($data, [0, 1], 3);
    is_deeply($w1, [5, 28, 4], 'max widths across rows 0 and 1');

    # Visible row 1 only
    my $w2 = get_visible_field_max_widths($data, [1], 3);
    is_deeply($w2, [3, 5, 4], 'max widths for row 1');

    # Empty visible rows
    my $w3 = get_visible_field_max_widths($data, [], 3);
    is_deeply($w3, [0, 0, 0], 'empty visible rows returns zeroes');
};

subtest 'adjust_column_widths --- expand to visible fields' => sub {
    my $orig_widths = [10, 10, 10];
    my $curr_widths = [10, 10, 10];
    my $is_hidden   = [0, 0, 0];
    my $header      = ['name', 'dept', 'score'];

    # Visible cols: 0 and 1. Visible max widths: col 0 has 5, col 1 has 30, col 2 has 40 (col 2 not visible)
    my $vis_cols   = { 0 => 1, 1 => 1 };
    my $vis_max_w  = [5, 30, 40];

    # 1. Empty input expands visible col 1 orig_width to 30, and since all were at full width, shrinks all to header width
    my ($ok, $msg) = adjust_column_widths(
        $orig_widths, $curr_widths, $is_hidden, $header,
        '', 3, $vis_cols, $vis_max_w
    );
    is($ok, 1, 'empty input succeeds');
    is($orig_widths->[0], 10, 'col 0 default width unchanged (visible field smaller than default)');
    is($orig_widths->[1], 30, 'col 1 default width expanded to 30');
    is($orig_widths->[2], 10, 'col 2 default width unchanged (not visible)');
    is_deeply($curr_widths, [4, 4, 5], 'all columns shrunk to header widths');

    # 1b. Next empty input restores all columns to expanded full widths
    adjust_column_widths($orig_widths, $curr_widths, $is_hidden, $header, '', 3, $vis_cols, $vis_max_w);
    is_deeply($curr_widths, [10, 30, 10], 'all columns restored to expanded full widths');

    # 2. 'w 1' on designated col 1 (which now has orig=30, curr=30): toggles to header length
    my $orig2 = [10, 20, 10];
    my $curr2 = [10, 20, 10];
    my $hid2  = [0, 0, 0];
    # Col 1 has visible field 35 (> 20)
    my ($ok2) = adjust_column_widths(
        $orig2, $curr2, $hid2, $header,
        '2', 3, { 1 => 1 }, [0, 35, 0]
    );
    is($orig2->[1], 35, 'w 2 expands col 2 orig_width to 35');
    is($curr2->[1], 35, 'w 2 expands col 2 curr_width to 35');

    # Subsequent 'w 2' toggles down to header length (4 for 'dept')
    my ($ok3) = adjust_column_widths(
        $orig2, $curr2, $hid2, $header,
        '2', 3, { 1 => 1 }, [0, 35, 0]
    );
    is($orig2->[1], 35, 'orig_width remains 35 after toggling down');
    is($curr2->[1], 4,  'curr_width toggled down to header length 4');

    # 3. Explicit width '2:15' does not alter orig_width
    my ($ok4) = adjust_column_widths(
        $orig2, $curr2, $hid2, $header,
        '2:15', 3, { 1 => 1 }, [0, 35, 0]
    );
    is($orig2->[1], 35, 'orig_width remains 35 when explicit width specified');
    is($curr2->[1], 15, 'curr_width set to explicit width 15');
};

subtest 'compile_regex pure function' => sub {
    # Valid patterns
    my ($qr1, $err1) = compile_regex('Alice');
    ok(defined $qr1, 'valid regex returns compiled regex');
    is($err1, undef, 'valid regex returns undef error');
    ok('Alice' =~ $qr1, 'compiled regex matches string');
    ok('Bob' !~ $qr1, 'compiled regex does not match non-matching string');

    my ($qr2, $err2) = compile_regex('^\d+\s+\w+$');
    ok(defined $qr2, 'valid complex regex compiles');
    is($err2, undef, 'valid complex regex returns undef error');
    ok('123 abc' =~ $qr2, 'complex regex matches expected pattern');

    # Invalid patterns
    my ($qr3, $err3) = compile_regex('[');
    is($qr3, undef, 'unclosed bracket regex returns undef regex');
    is($err3, 'Invalid regex: [', 'unclosed bracket returns formatted error message');

    my ($qr4, $err4) = compile_regex('(?');
    is($qr4, undef, 'incomplete group regex returns undef regex');
    is($err4, 'Invalid regex: (?', 'incomplete group returns formatted error message');

    my ($qr5, $err5) = compile_regex('+');
    is($qr5, undef, 'dangling quantifier regex returns undef regex');
    is($err5, 'Invalid regex: +', 'dangling quantifier returns formatted error message');

    # Empty and undef
    my ($qr6, $err6) = compile_regex('');
    is($qr6, undef, 'empty string returns undef regex');
    is($err6, undef, 'empty string returns undef error');

    my ($qr7, $err7) = compile_regex(undef);
    is($qr7, undef, 'undef returns undef regex');
    is($err7, undef, 'undef returns undef error');
};

subtest 'parse_cli_args pure function' => sub {
    # Default options
    my ($opts0, $err0) = parse_cli_args();
    is($err0, undef, 'no args returns no error');
    is($opts0->{delimiter}, "\t", 'default delimiter is tab');
    is($opts0->{csv}, 0, 'default csv mode is 0');
    is($opts0->{line_numbers}, 0, 'default line numbers is 0');
    is($opts0->{help}, 0, 'default help is 0');
    is_deeply($opts0->{files}, [], 'default files list is empty');

    # Delimiter flag -d and --delimiter
    my ($opts1, $err1) = parse_cli_args('-d', ',');
    is($err1, undef, '-d parsed without error');
    is($opts1->{delimiter}, ',', '-d sets delimiter to comma');

    my ($opts2, $err2) = parse_cli_args('--delimiter', '|');
    is($err2, undef, '--delimiter parsed without error');
    is($opts2->{delimiter}, '|', '--delimiter sets delimiter');

    # CSV flags -c and --csv
    my ($opts3, $err3) = parse_cli_args('-c');
    is($err3, undef, '-c parsed without error');
    is($opts3->{csv}, 1, '-c sets csv to 1');
    is($opts3->{delimiter}, ',', '-c defaults delimiter to comma');

    my ($opts4, $err4) = parse_cli_args('--csv');
    is($err4, undef, '--csv parsed without error');
    is($opts4->{csv}, 1, '--csv sets csv to 1');
    is($opts4->{delimiter}, ',', '--csv defaults delimiter to comma');

    # Line numbers flag -N and --numbers
    my ($opts5, $err5) = parse_cli_args('-N');
    is($err5, undef, '-N parsed without error');
    is($opts5->{line_numbers}, 1, '-N sets line_numbers to 1');

    my ($opts6, $err6) = parse_cli_args('--numbers');
    is($err6, undef, '--numbers parsed without error');
    is($opts6->{line_numbers}, 1, '--numbers sets line_numbers to 1');

    # Help flags -h and --help
    my ($opts7, $err7) = parse_cli_args('-h');
    is($err7, undef, '-h parsed without error');
    is($opts7->{help}, 1, '-h sets help to 1');

    my ($opts8, $err8) = parse_cli_args('--help');
    is($err8, undef, '--help parsed without error');
    is($opts8->{help}, 1, '--help sets help to 1');

    # File arguments preserved
    my ($opts9, $err9) = parse_cli_args('-d', ':', 'foo.tsv', 'bar.tsv');
    is($err9, undef, 'args with files parsed without error');
    is($opts9->{delimiter}, ':', 'delimiter option parsed correctly');
    is_deeply($opts9->{files}, ['foo.tsv', 'bar.tsv'], 'remaining args preserved in files');

    # Unknown option -n rejected
    my ($opts10, $err10) = parse_cli_args('-n');
    is($opts10, undef, 'unknown option -n returns undef opts');
    like($err10, qr/Unknown option:\s*n/i, 'unknown option -n error message returned');

    # Conflicting --csv and -d
    my ($opts11, $err11) = parse_cli_args('--csv', '-d', ',');
    is($opts11, undef, 'conflicting options return undef opts');
    like($err11, qr/Cannot specify both --csv and --delimiter/i, 'conflict error message returned');

    # Missing option argument
    my ($opts12, $err12) = parse_cli_args('-d');
    is($opts12, undef, 'missing delimiter argument returns undef opts');
    like($err12, qr/Option d requires an argument/i, 'missing argument error message returned');
};

done_testing();

