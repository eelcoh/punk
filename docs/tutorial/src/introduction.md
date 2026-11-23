# punk-lang

punk is a small language for real applications. It has Elm's syntax and
habits (whitespace, `f a b`, `|>`, `case ... of`, `Maybe`, hand-written JSON
decoders) and is compiled by the Roc compiler, on platforms whose hosts are
written in Rust. Most punk is written by agents and read by people, so it
aims for one thing: if it compiles, it runs.

## What you'll build

This tutorial starts from a Mac with nothing on it and ends with a JSON API
for notes, with its notes in Postgres:

1. [Install](install.md) punk, the VS Code extension, Rust and Postgres.
2. [Make a new app](new-app.md) with `punk new`: a git repository with the
   app, the server that runs it, and the instructions and skills for coding
   agents.
3. [Write the API](notes-api.md): a table, queries, JSON decoders and
   encoders, and routes.
4. [Change the table](migration.md) and let the server migrate the
   database.
5. [Run it in a container](container.md), with the database elsewhere and
   TLS to it.

It takes about half an hour, most of it waiting for downloads.

Every program in this tutorial is in the punk repository
([`examples/tutorial`](https://github.com/eelcoh/punk/tree/main/examples/tutorial)),
and its tests run them against a real Postgres, so the code here compiles
and works.
