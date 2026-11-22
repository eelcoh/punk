# punk-lang for VS Code

Support for [punk-lang](https://github.com/eelcoh/punk) (`.punk` files):

- **Syntax highlighting**: a TextMate grammar (`syntaxes/punk.tmLanguage.json`)
  for the whole language: headers and imports, `type` / `type alias`,
  annotations, `fn`, `case ... of`, `fold ... into ... with`, `try`, effect
  names ending in `!`, string interpolation `${...}`, Elm comments
  `--`, `{- -}` and `{-| -}`, and the query language's `table` declarations.
- **Formatting**: `punk fmt` is the formatter of `.punk` files, and runs on
  save (`editor.formatOnSave` is on for punk; turn it off per language).
- **Problems**: on open and on save, `punk check --json` runs on the file and
  its problems show in the editor and the Problems panel, with their stable
  codes (`P101`, `roc/type-mismatch`, ...). The command "punk: Check this
  file" runs it by hand.
- Comment toggling (`--`), brackets, and 4 spaces per indentation level.

## Install

Each release carries `punk-lang-<version>.vsix` (`code --install-extension` it), and publishes it on the Marketplace when the repository has the secret `VSCE_PAT`. Or build it from this folder:

```
cd editors/vscode
npx @vscode/vsce package        # makes punk-lang-0.1.0.vsix
code --install-extension punk-lang-0.1.0.vsix
```

Or, while working on the extension: open this folder in VS Code and press F5.

## Settings

| Setting | Default | |
|---|---|---|
| `punk.path` | `punk` | the `punk` command: a name on your `PATH` (install.sh links it into `~/.local/bin`), or a path; a relative path such as `zig-out/bin/punk` is relative to the workspace folder |
| `punk.checkOnSave` | `true` | run `punk check --json` on open and save |

## Test

```
npm ci
npm test
```

tokenizes a set of cases and every `.punk` file in `examples/` and
`packages/` with the tokenizer VS Code uses, and fails on a wrong scope, an
`invalid` scope or a comment or string left open.
