---
name: punk-migration
description: Use when changing a punk table declaration (columns, key, policies) or when punk check reports P405. Covers punk check --schema, migrate functions, and removing them afterwards.
---

# Change a table

The tables in the program are the truth. `schema.sql` next to the app is
their history, written by `punk check --schema`: never edit it by hand. The
wiring applies each new version once, in order, at startup.

## Steps

1. Change the row type (the `type alias` the `table` names) and/or the
   policy lines.
2. `punk check --json App.punk`. A `P405` means the tables now differ from
   `schema.sql`.
3. Decide whether existing rows need a migration:
   - **No migration** for: a new table, a new `Maybe` column (old rows get
     `Nothing`), or a changed policy.
   - **A migration** for anything else: a new non-`Maybe` column, a rename,
     a type change, a removed column.
4. If one is needed, write it next to the table: a function from the old row
   to the new one, run in the database for the rows that are there:

   ```elm
   migrate links
       fn old -> { old | createdAt = old.created, owner = "anonymous" }
   ```

   `createdAt = old.created` renames a column. A constant or an expression
   of the old row computes a new one (as in a query: no values from outside).
   An old column that the new row doesn't have is dropped.
5. `punk check --schema App.punk`. It adds the next version to `schema.sql`
   and reports what changed. Read the generated SQL.
6. **Remove the `migrate`**: once its version is in `schema.sql`, a
   leftover `migrate` is itself a `P405`.
7. Run the skill `punk-check-loop`, then the app's tests
   (`cargo test --locked` in `server/`, with `PUNK_TEST_POSTGRES`).

## Rules

- Commit `schema.sql` together with the change of the table.
- Never change or remove a version that is already in `schema.sql`: the
  wiring refuses a version that changed after it was applied.
- Policies are security. Narrowing one (`everyone` to a function of the
  user) is a change of behaviour, so say so in the PR.
