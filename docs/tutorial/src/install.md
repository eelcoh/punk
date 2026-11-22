# Install punk on a Mac

You need a terminal (Terminal.app is fine) and an internet connection. These
steps are for macOS on Apple silicon or Intel. On Linux, use your package
manager instead of Homebrew; the rest is the same.

## The developer tools

Rust needs Apple's linker. If you have never installed Xcode or its
command-line tools:

```sh
xcode-select --install
```

## punk

```sh
curl -fsSL https://raw.githubusercontent.com/eelcoh/punk/main/install.sh | sh
```

This downloads the latest release, checks it against its `SHA256SUMS`, and
puts it in `~/.punk`: the compiler, the platforms (`cli`, `server`, `tui`),
the `json` package, the skills for agents and the language reference
`llms.txt`. The command `punk` is linked into `~/.local/bin`. If that folder
is not on your `PATH` yet, the script says so. Add it to `~/.zshrc`:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Check it:

```sh
punk version
# punk-lang v0.1.1
```

To update later, run the same `curl` line again. Each version gets its own
folder in `~/.punk/versions`, and `~/.punk/current` is the one you use.

## VS Code and the punk extension

Install VS Code from <https://code.visualstudio.com>, open it, and run
**Shell Command: Install 'code' command in PATH** from the command palette
(⇧⌘P), so that `code` works in the terminal.

The extension gives you highlighting, `punk fmt` when you save, and the
compiler's problems in the editor. Download `punk-lang-<version>.vsix` from
the [latest release](https://github.com/eelcoh/punk/releases/latest) and
install it:

```sh
code --install-extension ~/Downloads/punk-lang-*.vsix
```

(Once the extension is on the Marketplace, searching for **punk-lang** in
the Extensions view does the same.)

## Rust

A punk server runs on a small Rust program, which `cargo` builds for you.
Install Rust with rustup:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

The first build of an app downloads the exact Rust version the platform
uses, so you don't have to pick one.

## Postgres

With [Homebrew](https://brew.sh):

```sh
brew install postgresql@17
brew services start postgresql@17
echo "export PATH=\"$(brew --prefix postgresql@17)/bin:\$PATH\"" >> ~/.zshrc
source ~/.zshrc
```

`brew services` starts Postgres now and whenever you log in. The third line
puts Postgres' commands (`psql`, `createdb`, `createuser`) on your `PATH`:
Homebrew leaves a versioned Postgres out of it. Homebrew makes
you a database user with your own Mac user name, so `psql postgres` works
without a password.

That's everything. Next: [a new app](new-app.md).
