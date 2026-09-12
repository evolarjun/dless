#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use POSIX qw(SIGTERM);

# ------ Helpers ------------------------------
my $dless    = "$Bin/../dless";
my $fixtures = "$Bin/fixtures";
my $SESSION  = "dless_test_$$";  # unique session name per test run

# Ensure tmux is available.
my $tmux = `which tmux 2>/dev/null`;
chomp $tmux;
plan skip_all => 'tmux not found' unless $tmux && -x $tmux;

# State tracking for failure diagnostics
my $current_cmd    = '';
my $current_width  = 80;
my $current_height = 24;
my @current_keys   = ();

# Launch dless in a tmux pane of fixed size and return the session name.
sub launch {
    my (%opts) = @_;
    my $cmd     = $opts{cmd}    // "$dless $fixtures/basic.tsv";
    my $width   = $opts{width}  // 80;
    my $height  = $opts{height} // 24;
    my $reuse   = $opts{reuse}  // 0;

    $current_cmd    = $cmd;
    $current_width  = $width;
    $current_height = $height;
    @current_keys   = ();

    if ($reuse && system("$tmux has-session -t $SESSION 2>/dev/null") == 0) {
        return $SESSION;
    }

    # Kill any stale session with the same name.
    system($tmux, 'kill-session', '-t', $SESSION) if system("$tmux has-session -t $SESSION 2>/dev/null") == 0;

    system($tmux, 'new-session', '-d', '-s', $SESSION, '-x', $width, '-y', $height, $cmd);
    for (1..20) {
        select(undef, undef, undef, 0.01);
        my $raw = `$tmux capture-pane -t $SESSION -p 2>/dev/null`;
        last if $raw =~ /\S/;
    }
    return $SESSION;
}

# Capture the pane content and strip ANSI escape sequences.
sub capture {
    my $raw = `$tmux capture-pane -t $SESSION -p 2>/dev/null`;
    $raw =~ s/\e\[[0-9;]*[mABCDHJKfsuhl]//g;  # strip ANSI
    return $raw;
}

# Send a key sequence to the running pane.
sub send_keys {
    my (@keys) = @_;
    push @current_keys, @keys;
    return unless @keys;
    system($tmux, 'send-keys', '-t', $SESSION, @keys);
    select(undef, undef, undef, 0.02);
}

# Kill the session and print diagnostics if the subtest failed.
sub teardown {
    my (%opts) = @_;
    my $tb = Test::Builder->new;
    if (!$tb->is_passing && $current_cmd) {
        my $msg = "\n  Failed command line:\n    $current_cmd";
        $msg .= "\n  Terminal size: ${current_width}x${current_height}" if $current_width != 80 || $current_height != 24;
        $msg .= "\n  Keys pressed in test: " . join(" -> ", @current_keys) if @current_keys;
        diag($msg . "\n");
    }
    unless ($opts{keep_alive}) {
        system("$tmux kill-session -t $SESSION 2>/dev/null");
    }
}

# ------------------------------------------------------------
# Suite 1: Initial Display & Status Bar
# ------------------------------------------------------------
subtest 'initial display and status bar' => sub {
    launch();
    my $screen = capture();
    unlike($screen, qr/1\s+2\s+3/, 'column numbers not visible on initial render');
    like($screen, qr/name/, 'header "name" is visible');
    like($screen, qr/age/,  'header "age" is visible');
    like($screen, qr/score/,'header "score" is visible');
    like($screen, qr/Alice/, 'first data row visible');
    like($screen, qr/Bob/,   'second data row visible');
    like($screen, qr/dless\/t\//, 'status bar shows path containing dless/t/');
    like($screen, qr/Rows\s+\d+-\d+\s+of\s+\d+/, 'status bar shows row range');
    like($screen, qr/Col offset:\s*0/, 'status bar shows horizontal offset = 0');
    teardown();
};

# ------------------------------------------------------------
# Suite 2: Help Overlay & Lifecycle
# ------------------------------------------------------------
subtest 'help overlay and lifecycle' => sub {
    launch();

    # '?' opens help
    send_keys('?');
    my $q_help = capture();
    like($q_help, qr/KEYBINDINGS/, 'help overlay shows KEYBINDINGS on ?');
    like($q_help, qr/Quit/,        'help overlay shows Quit binding on ?');
    send_keys('Escape');

    # 'h' opens help
    send_keys('h');
    my $h_help = capture();
    like($h_help, qr/KEYBINDINGS/, 'help overlay shows KEYBINDINGS on h');
    like($h_help, qr/Quit/,        'help overlay shows Quit binding on h');
    like($h_help, qr/C-b/,         'help overlay shows C-b binding');
    like($h_help, qr/&/,           'help overlay shows & binding');

    # Dismiss with any key (e.g. 'x')
    send_keys('x');
    my $alive = system("$tmux has-session -t $SESSION 2>/dev/null");
    is($alive, 0, 'session still alive after dismissing help with x');

    # 'q' quits viewer
    send_keys('q');
    select(undef, undef, undef, 0.1);
    my $after_q = system("$tmux has-session -t $SESSION 2>/dev/null");
    isnt($after_q, 0, 'session no longer exists after q');

    teardown();
};

# ------------------------------------------------------------
# Suite 3: Vertical Navigation & Scrolling
# ------------------------------------------------------------
subtest 'vertical navigation and scrolling' => sub {
    launch(height => 7);

    # Down one row
    my $before = capture();
    like($before, qr/Alice/, 'Alice visible before scroll');
    send_keys('Down');
    my $after_down = capture();
    unlike($after_down, qr/\bAlice\b/, 'Alice no longer in top data row after scroll');
    like($after_down,   qr/Bob/,       'Bob still visible after one scroll');

    # j and k keys
    send_keys('Home');
    send_keys('j');
    my $after_j = capture();
    unlike($after_j, qr/\bAlice\b/, 'Alice scrolled off after j');
    like($after_j,   qr/Bob/,       'Bob visible after j');

    send_keys('k');
    my $after_k = capture();
    like($after_k, qr/Alice/, 'Alice visible again after k');

    # Home and g keys
    send_keys('Down', 'Down', 'Down');
    my $mid = capture();
    unlike($mid, qr/\bAlice\b/, 'Alice not visible mid-scroll');
    send_keys('Home');
    my $top_home = capture();
    like($top_home, qr/Alice/, 'Alice visible again after Home');

    send_keys('Down', 'Down', 'Down');
    send_keys('g');
    my $top_g = capture();
    like($top_g, qr/Alice/, 'Alice visible again after g');

    # End and G jump to last row at bottom of view
    send_keys('End');
    my $screen_end = capture();
    like($screen_end, qr/Jack/, 'Jack visible after End');
    like($screen_end, qr/Rows 6-10 of 10/, 'End sets last row at bottom of view');

    send_keys('Home');
    send_keys('G');
    my $screen_g = capture();
    like($screen_g, qr/Jack/, 'Jack visible after G');
    like($screen_g, qr/Rows 6-10 of 10/, 'G sets last row at bottom of view');

    # Scroll past end of file until last row is top line
    for (1 .. 10) {
        send_keys('Down');
    }
    my $screen_eof = capture();
    like($screen_eof, qr/Jack/, 'Jack visible at top of view');
    unlike($screen_eof, qr/Iris/, 'Iris not visible when Jack is top line');
    like($screen_eof, qr/Rows 10-10 of 10/, 'status bar shows Rows 10-10 of 10');

    # Down again stays clamped at max_v
    send_keys('Down');
    my $screen_clamped = capture();
    like($screen_clamped, qr/Rows 10-10 of 10/, 'remains clamped at max_v after extra Down');

    # G returns to bottom position
    send_keys('G');
    my $screen_g_back = capture();
    like($screen_g_back, qr/Rows 6-10 of 10/, 'G jumps so last line is at bottom of view');
    like($screen_g_back, qr/Frank/, 'Frank visible after G');
    like($screen_g_back, qr/Jack/, 'Jack visible after G');

    # Pressing Down from bottom position scrolls past bottom
    send_keys('Down');
    my $screen_down_past = capture();
    like($screen_down_past, qr/Rows 7-10 of 10/, 'Down after G scrolls past bottom');
    unlike($screen_down_past, qr/Frank/, 'Frank scrolled off');

    # Page down past end of file
    send_keys('Home');
    send_keys('PgDn');
    my $p1 = capture();
    like($p1, qr/Rows 6-10 of 10/, 'first PgDn reaches bottom of file');

    send_keys('PgDn');
    my $p2 = capture();
    like($p2, qr/Rows 10-10 of 10/, 'second PgDn pages past end to max_v');
    like($p2, qr/Jack/, 'Jack visible at top line');

    teardown();
};

# ------------------------------------------------------------
# Suite 4: Page Scrolling Key Synonyms & Short File Scroll
# ------------------------------------------------------------
subtest 'page scrolling synonyms and short files' => sub {
    launch(cmd => "$dless $fixtures/basic.tsv", height => 8);

    # PgDn (NPage)
    my $before = capture();
    like($before, qr/Alice/, 'Alice visible before PgDn');
    send_keys('NPage');
    my $after_pgdn = capture();
    unlike($after_pgdn, qr/\bAlice\b/, 'Alice scrolled off after PgDn');

    # Space (PgDn synonym)
    send_keys('Home');
    send_keys('Space');
    my $after_space = capture();
    unlike($after_space, qr/\bAlice\b/, 'Alice scrolled off after Space');

    # Backspace (PgUp synonym)
    send_keys('BSpace');
    my $after_bspace = capture();
    like($after_bspace, qr/\bAlice\b/, 'Alice visible again after Backspace');

    # C-f and f (PgDn synonyms)
    send_keys('C-f');
    my $after_cf = capture();
    unlike($after_cf, qr/\bAlice\b/, 'Alice scrolled off after C-f');

    send_keys('Home');
    send_keys('f');
    my $after_f = capture();
    unlike($after_f, qr/\bAlice\b/, 'Alice scrolled off after f');

    # C-b (PgUp synonym)
    send_keys('C-b');
    my $after_cb = capture();
    like($after_cb, qr/\bAlice\b/, 'Alice visible again after C-b');

    teardown();

    # Short file in tall window (height 20 -> 18 visible data rows, 10 rows in basic.tsv)
    launch(height => 20);
    for (1 .. 10) {
        send_keys('j');
    }
    my $short_screen = capture();
    like($short_screen, qr/Rows 10-10 of 10/, 'short file scrolls until last row is top line');
    unlike($short_screen, qr/Alice/, 'Alice scrolled off');
    unlike($short_screen, qr/Iris/, 'Iris scrolled off');

    send_keys('G');
    my $short_g = capture();
    like($short_g, qr/Rows 1-10 of 10/, 'G in short file returns to offset 0');
    like($short_g, qr/Alice/, 'Alice visible again');

    teardown();
};

# ------------------------------------------------------------
# Suite 5: Horizontal Navigation & Wide Viewport
# ------------------------------------------------------------
subtest 'horizontal navigation and wide viewport' => sub {
    launch(cmd => "$dless $fixtures/wide.tsv", width => 80);

    # Right shifts content
    my $before = capture();
    like($before, qr/col1/, 'col1 header visible before scroll');
    send_keys('Right');
    my $after_right = capture();
    like($after_right, qr/Col offset:\s*10/, 'status bar shows offset 10 after one Right');

    # Left at offset 0 stays at 0
    send_keys('Left');
    my $at_zero = capture();
    like($at_zero, qr/Col offset:\s*0/, 'offset stays 0 at left boundary');

    # Tab scrolls right 4/5 viewport
    send_keys('Tab');
    my $after_tab = capture();
    unlike($after_tab, qr/\bcol1\b/, 'col1 scrolled off after Tab');

    # Shift-Tab scrolls left 4/5 viewport
    send_keys('BTab');
    my $after_shift_tab = capture();
    like($after_shift_tab, qr/col1/, 'col1 back after Shift-Tab');

    teardown();

    # -N flag freezes line numbers column during horizontal scroll
    launch(cmd => "$dless -N $fixtures/wide.tsv", width => 80);
    send_keys('Right');
    my $screen_n = capture();
    like($screen_n, qr/^\s*1\s+/m, 'line number 1 remains frozen on left after horizontal scroll');
    like($screen_n, qr/Col offset:\s*10/, 'horizontal scroll offset updated');
    teardown();
};

# ------------------------------------------------------------
# Suite 6: Display Toggles (Line Numbers & Column Numbers)
# ------------------------------------------------------------
subtest 'display toggles for line numbers and column numbers' => sub {
    # CLI -N flag
    launch(cmd => "$dless -N $fixtures/basic.tsv");
    my $screen_cli_n = capture();
    like($screen_cli_n, qr/^\s*1\s+Alice/m, 'line number 1 visible next to Alice');
    like($screen_cli_n, qr/^\s*10\s+Jack/m, 'line number 10 visible next to Jack');
    teardown();

    # Interactive N toggle
    launch(cmd => "$dless $fixtures/basic.tsv");
    my $before_toggle = capture();
    unlike($before_toggle, qr/^\s*1\s+Alice/m, 'line numbers not shown by default');

    send_keys('N');
    my $prompt_n = capture();
    like($prompt_n, qr/Constantly display line numbers/, 'prompt message shown after pressing N');
    unlike($prompt_n, qr/^\s*1\s+Alice/m, 'line numbers not shown until Enter is pressed');

    send_keys('Enter');
    my $after_n = capture();
    like($after_n, qr/^\s*1\s+Alice/m, 'line numbers shown after pressing Enter');

    send_keys('N');
    my $prompt_off = capture();
    like($prompt_off, qr/Don't use line numbers/, 'prompt message shown after pressing N when numbers on');

    send_keys('Enter');
    my $off_n = capture();
    unlike($off_n, qr/^\s*1\s+Alice/m, 'line numbers hidden after pressing Enter');

    # Pressing Esc after '-' cancels prompt
    send_keys('-');
    my $dash_prompt = capture();
    like($dash_prompt, qr/^\s*-\s*$/m, 'dash prompt active on status bar');

    send_keys('Escape');
    my $normal = capture();
    like($normal, qr/Rows \d+-\d+ of \d+/, 'returns to normal operation status bar after Esc');
    unlike($normal, qr/^\s*-\s*$/m, 'dash prompt cleared after Esc');

    # 1 and 0 keys toggle column numbers
    my $screen_init = capture();
    unlike($screen_init, qr/1\s+2\s+3/, 'column numbers hidden by default');

    send_keys('1');
    my $screen1 = capture();
    like($screen1, qr/1\s+2\s+3/, '1-based column numbers shown after pressing 1');

    send_keys('1');
    my $screen_off = capture();
    unlike($screen_off, qr/1\s+2\s+3/, 'column numbers hidden after pressing 1 again');

    send_keys('0');
    my $screen0 = capture();
    like($screen0, qr/0\s+1\s+2/, '0-based column numbers (0 1 2) shown after pressing 0');

    send_keys('0');
    my $screen_off2 = capture();
    unlike($screen_off2, qr/0\s+1\s+2/, 'column numbers hidden after pressing 0 again');

    send_keys('1');
    my $screen1_back = capture();
    like($screen1_back, qr/1\s+2\s+3/, '1-based column numbers restored after pressing 1');

    teardown();
};

# ------------------------------------------------------------
# Suite 7: Search & Filter Interactive Workflows
# ------------------------------------------------------------
subtest 'search and filter interactive workflows' => sub {
    launch(cmd => "$dless $fixtures/basic.tsv");

    # Search prompt and execution
    send_keys('/');
    my $prompt = capture();
    like($prompt, qr/\//, 'search prompt starts with /');

    send_keys('A', 'l', 'i', 'c', 'e', 'Enter');
    my $search_screen = capture();
    like($search_screen, qr/Alice/, 'Alice found and visible on screen');

    # n and p navigation with wrap around
    send_keys('n');
    my $wrap = capture();
    like($wrap, qr/wrapped/i, 'wrap message shown when wrapping search');

    send_keys('p');
    my $nav_p = capture();
    like($nav_p, qr/Alice/, 'navigated back to Alice');

    # Invalid regex handling
    send_keys('/', '[', 'Enter');
    my $invalid_screen = capture();
    like($invalid_screen, qr/Invalid regex/i, 'status bar shows invalid regex error message');

    # Clear search
    send_keys('/', 'Enter');
    my $cleared_search = capture();
    like($cleared_search, qr/Rows 1-/, 'clearing search restores standard status');

    # & filter option and empty expression clears
    send_keys('&');
    my $f_prompt = capture();
    like($f_prompt, qr/&/, 'filter prompt starts with &');

    send_keys('A', 'l', 'i', 'c', 'e', 'Enter');
    my $filtered = capture();
    like($filtered, qr/Alice/, 'Alice is visible when filtered');
    unlike($filtered, qr/Bob/, 'Bob is hidden when filtered');

    send_keys('&', 'Enter');
    my $all = capture();
    like($all, qr/Alice/, 'Alice visible after clearing filter');
    like($all, qr/Bob/,   'Bob visible again after clearing filter');

    # Search history recall with Up arrow
    send_keys('/', 'B', 'o', 'b', 'Enter');
    send_keys('/', 'Up');
    my $hist_prompt = capture();
    like($hist_prompt, qr/\/Bob/, 'search prompt recalled Bob via Up arrow');

    send_keys('Enter');
    my $hist_screen = capture();
    like($hist_screen, qr/Bob/, 'search for Bob executed successfully from history');

    # Filter history recall, edit with Backspace, and draft restoration
    send_keys('&', 'A', 'l', 'i', 'c', 'e', 'Enter');
    send_keys('&', 'Up');
    my $prompt_alice = capture();
    like($prompt_alice, qr/&Alice/, 'filter prompt recalled Alice via Up arrow');

    send_keys('BSpace', 'BSpace', 'BSpace', 'BSpace', 'BSpace', 'B', 'o', 'b', 'Enter');
    my $filtered_bob = capture();
    like($filtered_bob, qr/Bob/, 'Bob visible after editing recalled filter');
    unlike($filtered_bob, qr/Alice/, 'Alice hidden after editing recalled filter');

    send_keys('&', 'Up');
    my $p_bob = capture();
    like($p_bob, qr/&Bob/, 'newest filter history is Bob');

    send_keys('Up');
    my $p_alice = capture();
    like($p_alice, qr/&Alice/, 'previous filter history is Alice');

    send_keys('Down');
    my $p_bob_restored = capture();
    like($p_bob_restored, qr/&Bob/, 'Down arrow restored Bob');

    send_keys('Down');
    my $p_draft = capture();
    like($p_draft, qr/&[ ]*$/, 'Down arrow past newest restored empty draft');
    send_keys('Escape');

    # Multi-field search across column boundaries ('Alice\t30')
    send_keys('/', 'A', 'l', 'i', 'c', 'e', 'Tab', '3', '0', 'Enter');
    my $mf_search = capture();
    like($mf_search, qr/Alice/, 'Alice row found with multi-field search');

    # Multi-field filter across column boundaries ('Alice\t30')
    send_keys('&', 'A', 'l', 'i', 'c', 'e', 'Tab', '3', '0', 'Enter');
    my $mf_filter = capture();
    like($mf_filter, qr/Alice/, 'Alice is visible when multi-field filtered');
    unlike($mf_filter, qr/Bob/, 'Bob is hidden when multi-field filtered');

    # Clear filter
    send_keys('&', 'Enter');

    teardown();
};

# ------------------------------------------------------------
# Suite 8: Column Width Adjustments via 'w'
# ------------------------------------------------------------
subtest 'column width adjustments via w' => sub {
    launch(cmd => "$dless $fixtures/basic.tsv");

    # 1. Prompt and column number display
    my $initial = capture();
    unlike($initial, qr/1\s+2\s+3/, 'column numbers initially hidden');
    send_keys('w');
    my $prompt = capture();
    like($prompt, qr/w\s*/, 'w prompt active on status bar');
    like($prompt, qr/1\s+2\s+3/, '1-based column numbers temporarily shown during prompt');
    send_keys('Escape');
    my $cancelled = capture();
    unlike($cancelled, qr/1\s+2\s+3/, 'column numbers restored to hidden after Esc');

    # 2. Shrink column 1 to header length and toggle back
    send_keys('w', '1', 'Enter');
    my $shrunk = capture();
    like($shrunk, qr/Gra>/, 'col 1 truncated to 4 chars');

    send_keys('w', '1', 'Enter');
    my $restored = capture();
    like($restored, qr/Grace/, 'col 1 restored to full width');

    # 3. Custom width and hide column (1:0, 1:10, reset)
    send_keys('w', '1', ':', '0', 'Enter');
    my $hidden = capture();
    like($hidden, qr/\|\s+age/, 'col 1 header hidden with |');
    like($hidden, qr/\|\s+30/,  'col 1 data hidden with |');

    send_keys('w', '1', ':', '1', '0', 'Enter');
    my $custom = capture();
    like($custom, qr/name\s{7}age/, 'col 1 header expanded with custom width 10');
    like($custom, qr/Alice\s{7}30/, 'col 1 data row expanded with custom width 10');

    send_keys('w', 'Enter');
    my $reset = capture();
    like($reset, qr/name\s{2}age/, 'col 1 header reset to original width');
    like($reset, qr/Alice\s+30/,    'col 1 data row reset to original width');

    # 3b. Empty 'w' toggles all columns to header width when at full width
    send_keys('w', 'Enter');
    my $all_shrunk = capture();
    like($all_shrunk, qr/Gra>/, 'all columns shrunk to header width on empty w');

    send_keys('w', 'Enter');
    my $all_restored = capture();
    like($all_restored, qr/Grace/, 'all columns restored to full width on subsequent empty w');

    # 4. Hide column using N- synonym
    send_keys('w', '1', '-', 'Enter');
    my $hidden_dash = capture();
    like($hidden_dash, qr/\|\s+age/, 'col 1 header hidden with | using 1-');
    like($hidden_dash, qr/\|\s+30/,  'col 1 data hidden with | using 1-');

    send_keys('w', '1', 'Enter');
    my $restored_dash = capture();
    like($restored_dash, qr/name\s{2}age/, 'col 1 header restored after typing 1');

    # 5. Hide multiple adjacent columns as ||
    send_keys('w', '2', ':', '0', 'Enter');
    send_keys('w', '3', ':', '0', 'Enter');
    my $hidden_adj = capture();
    like($hidden_adj, qr/name\s+\|\|\s+city/, 'headers show || without spaces between adjacent hidden cols');
    like($hidden_adj, qr/Alice\s+\|\|\s+New York/, 'data rows show || without spaces between adjacent hidden cols');

    # 6. Multiple column specifiers on one line
    send_keys('w', '1', ' ', '2', ':', '0', ' ', '3', ':', '1', '2', 'Enter');
    my $multi_spec = capture();
    like($multi_spec, qr/Gra>/, 'col 1 shrunk to header length');
    like($multi_spec, qr/\|\s+score/, 'col 2 hidden with |');
    like($multi_spec, qr/\|\s{8}score city/, 'col 3 expanded to width 12');

    teardown();

    # 7. Expanding column widths to visible fields with large file
    my $late_wide_file = "$Bin/fixtures/large_late_wide.tsv";
    open my $fh, '>', $late_wide_file or die $!;
    print $fh "id\tname\tdescription\n";
    print $fh ("1\tBob\tshort\n" x 10000);
    print $fh "10001\tAlice\tThisIsAnExtremelyLongDescriptionFieldWayBeyondTenThousand\n";
    close $fh;

    launch(cmd => "$dless $late_wide_file", width => 120);
    send_keys('G');
    my $before_w = capture();
    like($before_w, qr/ThisIsAnEx>/, 'long field truncated before w');
    unlike($before_w, qr/ThisIsAnExtremelyLongDescriptionFieldWayBeyondTenThousand/, 'full field not visible before w');

    # First empty w shrinks all columns to header width and expands orig_width
    send_keys('w', 'Enter');
    my $after_w1 = capture();
    like($after_w1, qr/ThisIsAnEx>/, 'field truncated to header width after first empty w');

    # Second empty w restores all columns to expanded full width
    send_keys('w', 'Enter');
    my $after_w2 = capture();
    like($after_w2, qr/ThisIsAnExtremelyLongDescriptionFieldWayBeyondTenThousand/, 'full field visible after second empty w');

    send_keys('w', '3', 'Enter');
    my $toggled_down = capture();
    like($toggled_down, qr/ThisIsAnEx>/, 'field truncated again after w 3 toggled down to header');

    send_keys('w', '3', 'Enter');
    my $toggled_up = capture();
    like($toggled_up, qr/ThisIsAnExtremelyLongDescriptionFieldWayBeyondTenThousand/, 'field restored to expanded width after w 3');

    teardown();
    unlink $late_wide_file if -f $late_wide_file;
};

# ------------------------------------------------------------
# Suite 9: CLI Options, CSV Modes, Delimiters & Compression
# ------------------------------------------------------------
subtest 'cli options, csv modes, and compression' => sub {
    # Pipe input
    launch(cmd => "cat $fixtures/basic.tsv | $dless");
    my $pipe_screen = capture();
    like($pipe_screen, qr/name/,   'header visible from piped input');
    like($pipe_screen, qr/Alice/,  'data visible from piped input');
    like($pipe_screen, qr/stdin/i, 'status bar shows stdin for piped input');
    teardown();

    # Custom delimiter -d
    launch(cmd => "$dless -d , $fixtures/csv.csv");
    my $d_screen = capture();
    like($d_screen, qr/product/,  'CSV header "product" visible');
    like($d_screen, qr/price/,    'CSV header "price" visible');
    like($d_screen, qr/Widget/,   'CSV data visible');
    teardown();

    # Long delimiter --delimiter
    launch(cmd => "$dless --delimiter , $fixtures/csv.csv");
    my $delim_screen = capture();
    like($delim_screen, qr/product/, 'header visible with --delimiter');
    like($delim_screen, qr/Widget/, 'data visible with --delimiter');
    teardown();

    # CSV mode --csv and search
    launch(cmd => "$dless --csv $fixtures/quoted.csv");
    my $csv_screen = capture();
    like($csv_screen, qr/name/, 'header visible');
    like($csv_screen, qr/Widget, Basic/, 'embedded comma in quoted string preserved');
    like($csv_screen, qr/Widget "Pro"/, 'escaped quotes unescaped in display');
    like($csv_screen, qr/Multi-line\\ngadget/, 'embedded newline displayed as literal \\n');

    send_keys('/', 'W', 'i', 'd', 'g', 'e', 't', ' ', '"', 'P', 'r', 'o', '"', 'Enter');
    my $csv_search = capture();
    like($csv_search, qr/Widget "Pro"/, 'searched and matched unquoted string');
    teardown();

    # CSV short option -c
    launch(cmd => "$dless -c $fixtures/quoted.csv");
    my $c_screen = capture();
    like($c_screen, qr/Widget, Basic/, 'works with -c flag');
    teardown();

    # Decompression of gzip and zstd files
    launch(cmd => "$dless $fixtures/basic.tsv.gz", width => 100);
    my $gz_screen = capture();
    like($gz_screen, qr/name/, 'header visible from gzip file');
    like($gz_screen, qr/Alice/, 'data visible from gzip file');
    like($gz_screen, qr/basic\.tsv\.gz/, 'status bar shows gzip filename');
    teardown();

    launch(cmd => "$dless $fixtures/basic.tsv.zst", width => 100);
    my $zst_screen = capture();
    like($zst_screen, qr/name/, 'header visible from zstd file');
    like($zst_screen, qr/Alice/, 'data visible from zstd file');
    like($zst_screen, qr/basic\.tsv\.zst/, 'status bar shows zstd filename');
    teardown();

    # Decompression of piped gzip and zstd
    launch(cmd => "cat $fixtures/basic.tsv.gz | $dless");
    my $gz_pipe = capture();
    like($gz_pipe, qr/name/, 'header visible from piped gzip input');
    like($gz_pipe, qr/Alice/, 'data visible from piped gzip input');
    teardown();

    launch(cmd => "cat $fixtures/basic.tsv.zst | $dless");
    my $zst_pipe = capture();
    like($zst_pipe, qr/name/, 'header visible from piped zstd input');
    like($zst_pipe, qr/Alice/, 'data visible from piped zstd input');
    teardown();
};

done_testing();
