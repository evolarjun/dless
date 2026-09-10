# dless

`dless` is a terminal-based pager (TUI) for viewing tab-delimited or CSV data. It formats fields into fixed-width columns, keeps headers visible while scrolling vertically, and supports horizontal scrolling to inspect wide datasets. The UI is relatively simple and mostly follows [less(1)](https://linux.die.net/man/1/less). If you need anything more capable or sophisticated I recommend [VisiData](https://www.visidata.org) which has many more features.

## Prerequisites

- Perl 5 (with core modules: `strict`, `warnings`, `Getopt::Long`, `List::Util`, `POSIX`)
- `Term::ReadKey` CPAN module

Install the dependency using `cpan` or `cpanm`:

```sh
cpan Term::ReadKey
```

or:

```sh
cpanm Term::ReadKey
```

## Installation

`dless` is a standalone script. To install it, clone the repository or download the `dless` file, ensure it is executable, and place it in a directory listed in your `PATH`.

E.g.:
```sh
curl -o ~/bin/dless \
  https://raw.githubusercontent.com/aprasad/dless/main/dless \
  && chmod +x ~/bin/dless \
  && ln -s dless ~/bin/dl
```

For convenient viewing of csv files I also add the following to my `.bash_profile`

```sh
alias cl='dless --csv'
```
Ensure `~/bin` is in your `PATH` (for example, by adding `export PATH="$HOME/bin:$PATH"` to your shell profile).
