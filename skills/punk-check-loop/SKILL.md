---
name: punk-check-loop
description: Use whenever you write or change a .punk file. The loop that gets punk code to compile, punk fmt then punk check --json and fixing the first problem, plus what the common error codes usually mean.
---

# The punk check loop

punk's promise is "if it compiles, it runs", so most of the work is getting
the compiler to agree. Work in this loop, and don't run the app before the
loop is clean.

1. Write or change the file.
2. `punk fmt File.punk`. The formatter decides the layout, so don't fight
   it. If it says it left the file alone, the file has a syntax error: go to
   step 3.
3. `punk check --json File.punk`. It writes one JSON document on stdout:
   `errors`, `warnings` and `problems`, and each problem has a `code`, a
   1-based `line`/`column` in the `.punk` file and a `message`. Exit code 1
   means errors.
4. Fix **the first problem only**, then go back to step 2. Later problems are
   often caused by earlier ones.
5. When there are no errors and no warnings (a warning also fails a build),
   run the tests: `punk test File.punk` for `expect`s, and for a server or
   terminal app, `cargo test` in its Rust crate.

## What the codes usually mean

| Code | Usual cause | Usual fix |
|---|---|---|
| `P001` | Syntax: Roc or Elm habits such as `f(a, b)`, `\x ->`, `let ... in`, tabs, `{ }` bodies | punk syntax: `f a b`, `fn x ->`, a block of `name = value` lines, 4 spaces |
| `P101` / `P102` | `crash` / `dbg` outside an `expect` | return a `Result` or `Maybe` with your own error tag |
| `P201` | an exposed function of a module has no annotation | add `name : Type` above it |
| `P301` | SQL built with `${}` or `++` | a literal with `$1`, values as `Sql.text x` parameters |
| `P401` | a `table` misses a policy line or its key isn't a column | all four of `read`, `insert`, `update`, `delete` |
| `P402` | a query uses a function the database can't run | compute the value before the query, pass it in |
| `P403` | a column that isn't there, or a wrong type (also: sorting on `Bool`) | check the row type of the `table` |
| `P404` | a query the policy forbids, or `Db.runAs!` where no policy looks at the user | change the policy, or use `Db.run!` |
| `P405` | the tables differ from `schema.sql` | see the skill `punk-migration` |
| `roc/type-mismatch` | the types don't agree; the message shows both in punk syntax | read the expected type; often an argument order (value last, as in Elm) |
| `roc/name-not-in-scope` | a typo, a missing `import`, or a Roc name (`keep_if`) instead of punk's (`List.filter`) | use the names in `llms.txt` |

## Don't

- Don't silence a problem. That includes `crash`, `_ = ...` to drop a
  `Result`, and a catch-all `_ ->` branch that hides a case you should handle.
- Don't edit generated files (`schema.sql`, `llms.txt`).
- Don't add loops. There are none: use `List.*`, `fold`, or recursion.
