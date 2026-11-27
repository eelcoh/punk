# For agents working on this package

This is a [punk-lang](https://github.com/eelcoh/punk) library. Read the
language reference at `~/.punk/current/share/punk/llms.txt` (or
`src/punk/llms.txt` in the punk repository). See **Style → Design a package
API** for module exports, effects and tests.

`main.roc` lists the public modules. `test/PackageTest.punk` imports them
through the manifest. Use this app to check and test the package.

```
punk fmt Greeting.punk test/PackageTest.punk
punk check --json test/PackageTest.punk
punk test test/PackageTest.punk
```

The skill `punk-check-loop` explains the error codes.
