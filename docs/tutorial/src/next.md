# Next steps

You have a JSON API with a database, a migration, tests and a container.
Some things to try next:

- **Change a note.** Add `PUT /notes/<id>`. Ask your agent: with the skill
  `punk-endpoint` it adds the route, a decoder for the body, the query and a
  test, and runs the check loop until it is clean.
- **Users.** Give each note an `owner`, and make the policies functions of
  the user: `read fn user, note -> note.owner == user.id`. The app runs its
  queries with `Db.runAs!`, and Postgres keeps users apart.
  [`examples/notes`](https://github.com/eelcoh/punk/tree/main/examples/notes)
  shows how, with joins and transactions.
- **The language.** `~/.punk/current/share/punk/llms.txt` is the whole
  reference: syntax, the standard library, the platforms, the query
  language, and what each error code means.

Next in this tutorial: [a terminal app](tui.md) on the `tui` platform.
Coming: a unikernel.
