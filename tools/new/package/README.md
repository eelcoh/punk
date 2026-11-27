# @app@

A library in [punk-lang](https://github.com/eelcoh/punk). `main.roc` lists
the public modules. `Greeting.punk` is the starter module, and
`test/PackageTest.punk` imports it the way a consumer does.

```
punk fmt --check Greeting.punk test/PackageTest.punk
punk check --json test/PackageTest.punk
punk test test/PackageTest.punk
```

For an app beside the `@app@/` checkout, add the package manifest to the
app header under an alias and import the module through that alias.

```
app [main!] { Platform: platform "cli", Library: "@app@/main.roc" }

import Library.Greeting
import Platform.Stdout

main! : () => {}
main! = fn () ->
    Stdout.line! (Greeting.forName "world")
```

The path is relative to the app file. The library receives data from the
app, which holds the platform capabilities. `AGENTS.md` links to the
package style guidance.
