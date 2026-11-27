# punk-lang (punk)

> punk-lang ("punk") is an Elm-like language on top of the Roc compiler: Elm's
> syntax, names and argument order, Roc's types, platforms and speed. Files end
> in `.punk`. This file is everything you need to write punk programs.

If you know Elm, write Elm and read the section "Differences from Elm".
Everything not listed there works as in Elm.

## Tools

`zig build` installs the `punk` command at `zig-out/bin/punk`.

| Command | What it does |
|---------|--------------|
| `punk check --json app.punk` | Type-check without building. Problems as JSON on stdout (see "Errors"). Exit code 1 when there are errors. Fast (under a second). |
| `punk fmt app.punk ...` | Lay files out in the one canonical form. `--check` only lists files that are not formatted. |
| `punk fmt --stdin --path app.punk` | Format stdin to stdout, resolving imports relative to `app.punk` and leaving it untouched. |
| `punk app.punk [args]` | Build and run the app. |
| `punk test app.punk` | Run the `expect` tests in the file. |
| `punk new server notes` | A new app (`cli`, `server` or `tui`) in the folder `notes`, with its `AGENTS.md` and the skills. Only an installed punk has it. |

Work in this loop: write the file, `punk fmt` it, `punk check --json` it, fix
the first problem, repeat; then run it. Fix problems from the top: a later one
is often caused by an earlier one.

## A program

```
app [main!] { Platform: platform "cli" }

import Platform.Stdout

main! = fn () ->
    Stdout.line! "Hello"
```

`platform "cli"` names one of the platforms that come with punk: `cli`,
`server` or `tui`. In the same way `Json: "json"` names a package that comes
with punk (now only `json`). (A path to a platform's or package's `main.roc`,
relative to the `.punk` file, works too.) A file is an `app`
(it has `main!`) or a `module` (see "Modules").

## Syntax

```
-- a line comment
{- a block comment -}
{-| a doc comment, before a definition -}

answer : Int                      -- type annotation, then the definition
answer = 42

add : Int -> Int -> Int           -- functions are curried, as in Elm
add = fn a, b ->                  -- a lambda: `fn` params `->` body
    a + b

inc = add 1                       -- partial application
twice = fn f, x -> f (f x)        -- application by spaces: `f a b`, never `f(a, b)`

area = fn shape ->
    case shape of                 -- `case ... of`, as in Elm
        Circle r -> 3.14 * r * r
        Rect w h -> w * h

sign = fn n ->
    if n < 0 then -1 else if n == 0 then 0 else 1
```

Indentation is significant (4 spaces per level; tabs are an error). A body
on the next line is a block: any number of `name = value` lines and then the
result. There is no `let ... in`:

```
distance = fn a, b ->
    dx = a.x - b.x
    dy = a.y - b.y
    F64.sqrt (dx * dx + dy * dy)
```

Pipelines go line by line. `x |> f a` is `f a x`: the value goes last.

```
total =
    input
        |> String.lines
        |> List.map String.trim
        |> List.filter (fn line -> not (String.isEmpty line))
        |> List.length
```

### Values

| Kind | Syntax |
|------|--------|
| numbers | `42`, `-3`, `3.14`, `0xff`, `1_000_000` |
| strings | `"text"`, interpolation `"n = ${String.fromInt n}"` (only a `Str` goes inside `${}`), `"""` multi-line `"""` |
| characters | `'a'` |
| lists | `[1, 2, 3]`, `xs ++ ys` |
| tuples | `(1, "a")`; fields `.0`, `.1`: `pair.0`, `List.map .0 pairs` |
| records | `{ name = "Ann", age = 7 }`, `person.name`, `.name` (accessor function), update `{ person | age = 8 }`, field punning `{ name, age }` |
| tags | `Red`, `Circle 2.0`, `Ok 1`, `Err (BadLine line)`, `Just x`, `Nothing` |
| unit | `()` (argument of `main!` and other effects with no input), `{}` (empty record, the result of an effect such as `Stdout.line!`) |

### Operators

`+ - * /` (`/` on floats), `//` (integer division), `%` (remainder),
`== /= < <= > >=`, `&& ||`, `not x`, `++` (lists and strings), `|>`, `<|`.
A range of numbers is `List.range 1 5` (`[1, 2, 3, 4, 5]`). Dividing an
integer by zero gives 0, as in Elm.

### Types

```
type Shape = Circle Float | Rect Float Float     -- a union (custom type)

type Tree a
    = Leaf
    | Node (Tree a) a (Tree a)

type alias Point = { x : Int, y : Int }         -- a record type

parse : Str -> Result (List Int) _              -- `_`: let the compiler infer it
```

Builtin types: `Int` (64-bit, `I64`), `Float` (`F64`), `Bool` (`True`,
`False`), `Str`, `List a`, `Dict k v`, `Set a`, `Maybe a` (`Just a |
Nothing`), `Result ok err` (`Ok ok | Err err`), `Order` (`LT | EQ | GT`), and
Roc's sized numbers `U8 U16 U32 U64 I8 I16 I32 I64 F32 F64 Dec`.

Your own types, tuples, records, lists and strings support `==` and can be
`Dict` keys and `Set` members: `Dict (Int, Int) Int` is the usual grid.

### Numbers and characters

A number literal gets its type from where it is used; give a top-level
value an annotation (`total : U64`) when it matters. `Int` and `I64` are the
same type, as are `Float` and `F64`. Convert between sized numbers with the
functions of the source type:

| From to | Function |
|---------|----------|
| `U64` to `Int`, `Int` to `U64` | `toInt n`, `fromInt n` |
| always fits (`U8` to `I64`, `I32` to `I64`, ...) | `U8.toI64 b`, `I32.toI64 n` |
| may not fit | `I64.toU8Try n` (a `Result`), or `I64.toU8Wrap n` (wraps around) |
| to and from text | `I64.toStr n`, `U64.fromStr s` (a `Result`), `String.fromInt`, `String.toInt` (a `Maybe`) |

Use `Int.checkedAdd`, `Int.checkedSub`, `Int.checkedMul` and `Int.checkedDiv`
when arithmetic can fail. They take the right operand first, so
`7 |> Int.checkedSub 2` gives `Ok 5` and `7 |> Int.checkedDiv 2` gives `Ok 3`.
Division truncates toward zero. All four return `Err Overflow` when the
result does not fit in `Int`; division returns `Err DivByZero` for a zero
divisor. Match on the result or propagate the error with `try`.

A character literal `'a'` is a number (its code). `Str.toUtf8 s` gives the
bytes of a string as `List U8`, and `'0'` compares with them, so the digit of
a byte `b` is `U8.toI64 (b - '0')`.

### Errors are tags

Errors are tags; you do not have to declare an error type. A function that can
fail returns `Result value _` and makes up the error tags it needs:
`Err (BadLine line)`. A caller matches on them or passes them on with `try`.

### Patterns

In `case`, in lambda parameters and on the left of `=`:

```
case xs of
    [] -> "empty"
    [x] -> "one"
    [first, second, ..] -> "two or more"
    [first, ..rest] -> "first and the rest"

fn (a, b) -> a + b                      -- tuple
fn { x, y } -> x + y                    -- record
case r of
    Ok n if n > 0 -> "positive"         -- guard
    Ok _ -> "not positive"
    Err (BadLine line) -> line
    Err _ -> "other error"
```

### Errors with `try`

`try` before a call that returns a `Result` unwraps an `Ok`, or returns the
`Err` from the enclosing function at once:

```
parseLine : Str -> Result (I64, I64) _
parseLine = fn line ->
    case String.split "," line of
        [a, b] -> Ok (try I64.fromStr a, try I64.fromStr b)
        _ -> Err (BadLine line)

parseAll : Str -> Result (List (I64, I64)) _
parseAll = fn text ->
    pairs =
        text
            |> String.lines
            |> try List.mapTry parseLine  -- `try` in a pipeline checks the result
    Ok pairs
```

`try` takes one call (`try f a b`); for more use parentheses:
`try (s |> String.trim |> parse)`. There is no postfix `?`.

### Loops: `fold`

There is no `var`, `for`, `while` or `return`. Use `List.map`, `List.filter`,
recursion, or `fold`:

```
fold xs into 0 with fn x, total -> total + x       -- inline form

xs |> fold into 0 with add                          -- the list from a pipe

fold x in xs into total = 0                         -- block form, one accumulator:
    total + x                                       -- the body is its new value

fold x in xs into count = 0, sum = 0                -- more accumulators: the body is a
    if x > 0 then { count = count + 1, sum = sum + x } else {}
                                                    -- record of the ones that change;
                                                    -- the fold's value is a record of all
```

### Effects

A name ending in `!` does something (prints, reads a file). Call effects only
from other `!` functions; `main!` is the start. Each effect is one line in a
block:

```
main! = fn () ->
    text = Stdin.readAll! ()
    Stdout.line! "read ${String.fromInt (String.length text)} bytes"
```

### Tests

```
expect add 1 2 == 3
```

Top-level `expect`s run with `punk test`. `crash` and `dbg` are only allowed
inside an `expect` (rules P101, P102).

### Modules

```
module Grid exposing (Grid, at, Cell(..))      -- (..) exposes the tags too

import Grid exposing (Grid, at)                -- in another file: Grid.punk next to it
import Grid                                    -- then use Grid.at
```

Everything a module exposes needs a type annotation (rule P201).

## Differences from Elm

| Elm | punk |
|-----|------|
| `\x -> x + 1` | `fn x -> x + 1`, several parameters `fn a, b -> ...` |
| `let a = 1 in a + 2` | a block: `a = 1` on one line, `a + 2` on the next |
| `String` type | `Str` (the module is still `String`: `String.split`) |
| `Int` is JS-sized | `Int` is 64-bit; `List.len`, `List.get`, `List.countIf`, `Dict.len` use `U64` (convert with `toInt` / `fromInt`) |
| `"a" ++ String.fromInt n` | works, but `"a${String.fromInt n}"` is the usual way |
| `Debug.log` | `dbg`, only inside `expect` |
| `Maybe` everywhere | Roc's functions return `Result` (`List.first`, `List.get`, `Dict.get`); the Elm-only ones return `Maybe` (`List.head`, `String.toInt`) |
| `List.filterMap` with `Maybe` | `List.filterMap` keeps the `Ok`s of a function that returns a `Result` |
| `case` on `x :: xs` | list patterns `[x, ..xs]`; `::` does not exist |
| `(+)`, `(::)` | write a lambda: `fn a, b -> a + b` |
| `Html`, `Browser` | not yet; programs are command-line apps, servers or terminal apps on a platform |
| `Cmd`, `Sub`, `Browser.element` | the tui platform: `init`, `update`, `view`, `subscriptions`, `Cmd` and `Sub` (see "The tui platform") |
| `port`, `Task` | effects are `!` functions |
| `type alias Model = {...}` | same |
| `/=` | same (`!=` works too; write `/=`) |
| a module per file, `exposing` | same; the file name is the module name |

## Differences from Roc

You may know Roc. punk is Roc with Elm's surface; do not write Roc syntax:

| Roc | punk |
|-----|------|
| `\|a, b\| a + b` | `fn a, b -> a + b` |
| `f(a, b)` | `f a b` |
| `List.map(xs, f)`, `xs.map(f)` | `List.map f xs`, `xs \|> List.map f` |
| `match x { A => 1, B => 2 }` | `case x of` with `A -> 1` lines |
| `if c { a } else { b }` | `if c then a else b` |
| `x?` | `try x` |
| `List.keep_if`, snake_case | `List.filter` (Elm name) or `List.keepIf`; camelCase everywhere |
| `List.walk(xs, 0, \|s, x\| ...)` | `List.foldl (fn x, s -> ...) 0 xs`: the state comes last in the lambda |
| `Shape := [Circle(F64)]` | `type Shape = Circle F64` |
| `# comment` | `-- comment` |
| `var`, `for`, `while`, `return` | `fold`, recursion, `List.*` |

Roc functions without an Elm name exist too, in camelCase, with the value
they work on last: `Str.splitOn "," text`, `List.dropIf`, `U64.toStr n`.
Number functions keep Roc's order: `U64.toStr n`, `U64.fromStr s`,
`I64.toStr n`, `F64.toStr x`, `U64.absDiff a b`, `F64.sqrt x`.

## Errors

`punk check --json` writes one JSON document:

```
{
  "file": "app.punk",
  "errors": 1,
  "warnings": 0,
  "problems": [
    {
      "severity": "error",
      "code": "roc/name-not-in-scope",
      "title": "Name Not In Scope",
      "file": "app.punk",
      "line": 7, "column": 34, "endLine": 7, "endColumn": 44,
      "message": "Nothing is named notDefined in this scope. ...",
      "fix": null
    }
  ]
}
```

Positions are 1-based and in the `.punk` file. `code` is stable:

| Code | Meaning |
|------|---------|
| `P001` | punk syntax error (the message says what was expected) |
| `P101` | `crash` outside an `expect`: return a `Result` or `Maybe` instead |
| `P102` | `dbg` outside an `expect` |
| `P201` | an exposed value of a module has no type annotation |
| `P301` | the SQL of `Sql.query` is not a string literal: pass values as parameters (`$1`) |
| `P303` | the SQL of `Sql.query` names a table the module doesn't declare or a column it doesn't have, gives a parameter of another type than its column (`hits > $1` wants `Sql.int`), or the list doesn't have `$1` up to the last parameter |
| `P302` | a Mongo collection or field name (`Mongo.collection`, `Filter.*`, `Update.*`, `Mongo.sortBy`) is not a string literal, or is empty or starts with `$` |
| `P401` | a `table` declaration: its row type is not a record of storable columns, its key is not a column, or a policy line is missing |
| `P402` | a query that can't run in the database: not a pipeline from a table to `Db.all`/`first`/`update`/`delete`, or a function the database can't run |
| `P403` | a query uses a column the table doesn't have, or a value of the wrong type |
| `P404` | a query does what the table's policy forbids (`delete nobody`), or `Db.runAs!` where no policy looks at the user |
| `P405` | the tables differ from `schema.sql`: run `punk check --schema`, with a `migrate` when rows change; or a `migrate` that is done |
| `roc/<title>` | a problem the type checker found, such as `roc/type-mismatch`, `roc/name-not-in-scope`, `roc/missing-method` |

Warnings (`severity: "warning"`) do not stop the program. A warning
`roc/unconditional-condition` on `main!` for a value known at compile time
(such as an example input in the file) is harmless.

Some type-checker messages mention Roc syntax (`.toStr()`, `List.len`): read
them as the punk spelling (`String.fromInt`, `List.length`).

## The platform

`cli` (`app [main!] { Platform: platform "cli" }`) provides:

```
Stdout.line! : Str => {}             -- prints a line
Stdout.write! : Str => {}            -- prints without a newline
Stderr.line! : Str => {}
Stdin.line! : () => Str              -- one line, "" at the end of the input
Stdin.readAll! : () => Str
File.read! : Str => Result Str [FileErr Str]
File.write! : Str -> Str => Result {} [FileErr Str]   -- path, text
Arg.list! : () => List Str           -- the arguments after the program name
Clock.now! : () => I64               -- milliseconds since 1970 (Elm's posixToMillis)
Clock.elapsed! : () => I64           -- milliseconds since the program started
Random.u64! : () => U64              -- 64 random bits from the OS
```

`File.read!` and `File.write!` only work on files named on the command line
(`punk app.punk input.txt`); any other path gives `Err (FileErr msg)`. Take
the path from `Arg.list!`, never write a file name into the program.

Import what you use: `import Platform.Stdout`, `import Platform.File`, ...

A package name may be capitalized, as modules are: `{ Platform: platform
"...", Json: "..." }` with `import Platform.Stdout` and `import Json.Decode
as D`. All examples use it; lowercase `pf` and `json` keep working.

### The server platform

`platforms/server` is for HTTP servers (on ambit's server platform). The app
is a decoder for its settings and one function, called for every request
with the settings and the request:

```
app [Settings, main] { Platform: platform "server" }

import Platform.Http exposing [Request, Response]
import Platform.Config

main =
    { settings = settings, handle! = handle! }

-- What the app needs from the server's settings; `Config.succeed {}` for none.
type alias Settings =
    { greeting : Str
    }

settings : Config.Decoder Settings
settings =
    Config.map (fn greeting -> { greeting = greeting })
        (Config.text "GREETING" |> Config.withDefault "hello")

handle! : Settings -> Request => Response
handle! = fn config, req ->
    case toRoute req of
        Just Hello -> { status = 200, headers = [], body = Str.toUtf8 "${config.greeting}\n" }
        Just (Greet name) ->
            { status = 200, headers = [], body = Str.toUtf8 "${config.greeting} ${name}\n" }
        Nothing -> { status = 404, headers = [], body = [] }

-- The app's own type: one tag per route.
type Route
    = Hello
    | Greet Str

toRoute : Request -> Maybe Route
toRoute = fn req ->
    case (Http.method req, Http.segments req) of
        (Get, ["hello"]) -> Just Hello
        (Get, ["hello", name]) -> Just (Greet name)
        _ -> Nothing

expect toRoute (Http.request Get "/hello/ann") == Just (Greet "ann")
```

Route with a `case` on `(Http.method req, Http.segments req)` into a
`type Route` of the app's own, not on the text of `req.path`: the `case` in
`handle!` then has to cover every route, and `toRoute` is a pure function
to test with `expect`.

```
Request : { method : Str, path : Str, query : Str, headers : List (Str, Str), body : List U8 }
Response : { status : U16, headers : List (Str, Str), body : List U8 }
Http.method : Request -> Http.Method                -- Get | Head | Post | Put | Patch | Delete | Options | Other Str
Http.segments : Request -> List Str                 -- "/notes/n1/" is ["notes", "n1"], each part percent-decoded
Http.header : Str -> Request -> Maybe Str          -- a header, the name in any case: Http.header "authorization" req
Http.request : Http.Method -> Str -> Request        -- a request to test a router on: Http.request Get "/notes?all=1"
Kv.get! : Str => Result (Maybe Str) [KvErr Str]
Kv.put! : Str -> Str => Result {} [KvErr Str]      -- key, value
Kv.delete! : Str => Result {} [KvErr Str]
Clock.now! : () => I64                              -- milliseconds since 1970
Time.now! : () => Posix                             -- import Platform.Time exposing [Posix]
Time.posixToMillis : Posix -> Int                   -- also Time.millisToPosix : Int -> Posix
Time.toIso8601 : Posix -> Str                       -- "2026-11-24T12:14:20.123Z"
Time.fromIso8601 : Str -> Maybe Posix               -- Z or an offset (+01:00); Nothing for anything else
Uuid.generate! : () => Uuid                         -- import Platform.Uuid; version 7, ids made later sort later
Uuid.toString : Uuid -> Str                         -- "019ab5c4-1e2f-7a3b-9c4d-5e6f7a8b9c0d"
Uuid.fromString : Str -> Maybe Uuid                 -- either case, with or without the dashes
Random.u64! : () => U64
Log.info! : Str => {}                               -- also Log.warn!, Log.error!
```

Header names in a request are lower case.

Settings are text the wiring gives by name (environment variables it lists
in `SETTINGS` in `server/src/lib.rs`). The `settings` decoder types them;
the server runs it when it starts and refuses to start, naming every
setting that is missing or wrong. A password, key or token is a `Secret`,
never a `Str`: it can't become text, so it can't reach a log or a response.

```
Config.text : Str -> Config.Decoder Str             -- the setting with this name: Config.text "BASE_URL"
Config.int : Str -> Config.Decoder Int              -- "3600"
Config.bool : Str -> Config.Decoder Bool            -- "true" or "false"
Config.secret : Str -> Config.Decoder Secret        -- not empty; a message about it never shows it
Config.withDefault : a -> Config.Decoder a -> Config.Decoder a    -- when missing: Config.int "PORT" |> Config.withDefault 8080
Config.maybe : Config.Decoder a -> Config.Decoder (Maybe a)
Config.map : (a -> b) -> Config.Decoder a -> Config.Decoder b     -- also map2 .. map6, as Json.Decode
Config.succeed : a -> Config.Decoder a              -- also Config.fail : Str -> .., Config.andThen
Config.decode : Config.Decoder a -> List (Str, Str) -> Result a Str   -- for tests: Config.decode settings [("BASE_URL", "x")]
Secret.matches : Str -> Secret -> Bool              -- constant time: Secret.matches token config.apiKey
Secret.fromText : Str -> Secret                     -- for tests only; import Platform.Secret
```

The app has no other way to reach
the world: no files, no network, no environment. It is not run with
`punk app.punk`: `punk build` makes an archive that a small Rust crate links
and tests (see `platforms/server/README.md` and `examples/shortener/`).
Annotate an effect with more arguments as `Settings -> Str => Result Response _`.

### Postgres: tables and queries

Declare a table in punk, with the type of its rows, its key and who may
read, insert, update and delete its rows (a table without all four doesn't
compile, P401). Queries are pipelines from the table; punk turns each one
into one SQL statement with parameters, and checks the columns and their
types. `punk check --schema app.punk` writes `schema.sql` next to the app:
the versions of the tables, which the wiring applies in order.

```
import Platform.Db
import Platform.Time exposing [Posix]
import Platform.Uuid

type LinkId = LinkId Uuid

type alias Link =
    { id : LinkId
    , url : Str
    , created : Posix
    }

table links : Link
    key id
    read everyone
    insert everyone
    update nobody
    delete nobody

findLink : LinkId -> Db.Query (Maybe Link)
findLink = fn id ->
    links
        |> Db.filter (fn link -> link.id == id)
        |> Db.first

-- in an effect: case try Db.run! (findLink id) of ...
-- a new one: Db.insert { id = LinkId (Uuid.generate! ()), url, created = Time.now! () } links
```

A column is a `Str`, `Int`, `Float`, `Bool`, `Posix` (`timestamptz`),
`Uuid` (`uuid`), `Dec` (`numeric`, exact) or `Value` (`jsonb`, needs `import
Json.Value`), a `Maybe` of one (nullable), or a type of the program with
one tag that holds one of these (`type LinkId = LinkId Uuid`). Give ids such
a type: the database stores what it holds, and a query only compares it with
the same type (`link.id == "x"` is P403). For JSON, `Time.toIso8601` and
`Time.fromIso8601`, `Uuid.toString` and `Uuid.fromString` (a `Maybe`); route
an id with `Maybe.map ShowLink (Uuid.fromString id)`. A `Dec` goes to JSON
with `E.dec` and comes from it with `D.dec`; sums and averages of a `Dec` stay
`Dec`. A `Value` column is only compared with `Nothing` in a query (no order,
no `==`): decode it afterwards with `D.decodeValue`, and keep in mind that
Postgres reorders the keys of a `jsonb` object.

A policy can also be a function of the user and the row. It becomes a
Postgres row-level security policy, so the database itself keeps to it, also
for SQL by hand. Run a query as the user with `Db.runAs!`; with `Db.run!` the
user is nobody, and a policy that looks at the user is false.

```
table notes : Note
    key id
    read fn user, note -> note.public || note.owner == user.id
    insert fn user, note -> note.owner == user.id
    update fn user, note -> note.owner == user.id
    delete nobody

-- in an effect: notes = try Db.runAs! { id = "ann" } (notes |> Db.all)
```

The fields of the user (`user.id`) get their type from the column they meet,
and Roc checks that the record given to `Db.runAs!` has them. A policy uses
the columns, the fields of the user and constants. The app's database role
must keep to row-level security: the host refuses a superuser or a role with
`BYPASSRLS`.

A module can declare tables and expose them (`module Tables exposing
(Note, notes)`); a module that imports them (`import Tables exposing (notes)`)
starts queries from `notes` or `Tables.notes`. The app's `schema.sql` holds
every table of the program, also those of the modules it imports, and a
`migrate` stays in the module next to its table. A tag of another module's
type is written `Tables.UserId` (or `UserId` when the import exposes
`UserId(..)`).

When a table changes, the program doesn't compile (P405) until `punk check
--schema` has added a version to `schema.sql`. A new table, a new `Maybe`
column and a new policy need nothing more; any other change needs a
migration from the old row to the new one, which is removed again once the
version is in `schema.sql`:

```
migrate links
    fn old -> { old | createdAt = old.created, owner = "anonymous" }
```

`createdAt = old.created` renames a column, another value is computed in the
database for the rows there are (as in a query, without values from
outside), and an old column the new row doesn't take is dropped. A constant time is
`Time.millisToPosix 0`.

A renamed table says `migrate links from urls` (with a function below it when
its columns change too); a table that goes, with its rows, is `remove table
visits`. A table gone from the program without one of these doesn't compile.

```
Db.join : table -> (row -> row2 -> Bool) -> query -- JOIN ... ON; the steps after it take a row of each
Db.leftJoin : table -> (row -> row2 -> Bool) -> query -- LEFT JOIN: the steps after it take a row and a Maybe row2
Db.filter : (row -> Bool) -> query -> query       -- several filters: AND
Db.groupBy : (row -> key) -> query -> query       -- GROUP BY: the steps after it take the key and the rows
                                                  -- a Db.filter after it keeps groups: HAVING
Db.count : rows -> Int                            -- in the map after a groupBy: COUNT(*)
Db.sum : (row -> number) -> rows -> number        -- SUM; Db.min, Db.max keep the column type
Db.avg : (row -> number) -> rows -> Float         -- AVG
Db.sortBy : (row -> key) -> query -> query        -- ORDER BY ... ASC; the last sortBy decides first
Db.sortByDescending : (row -> key) -> query -> query
Db.drop : Int -> query -> query                   -- OFFSET
Db.take : Int -> query -> query                   -- LIMIT
Db.map : (row -> b) -> query -> query             -- .url, or a record { url = l.url, ... }
Db.all : query -> Db.Query (List row)             -- ends a query
Db.first : query -> Db.Query (Maybe row)          -- LIMIT 1
Db.insert : row -> table -> Db.Query Int          -- the number of rows changed
Db.insertIfNew : row -> table -> Db.Query Int     -- ON CONFLICT DO NOTHING: 0 when the key is taken
Db.update : (row -> row) -> query -> Db.Query Int -- (fn l -> { l | url = new }), after filters
Db.delete : query -> Db.Query Int
Db.run! : Db.Query a => Result a _                -- errors: PgErr { code, message }, RowErr Str
Db.runAs! : user -> Db.Query a => Result a _      -- as the user, for the policies; 42501 when one refuses
Db.transaction! : ({} => Result a e) => Result a e        -- Ok commits, Err rolls back
Db.transactionAs! : user -> ({} => Result a e) => Result a e
Db.toSql : Db.Query a -> Str
```

Joins, sorting and paging stay one SQL statement. The steps come in this
order: `join` (or `leftJoin`), `filter`, `groupBy` (and filters of groups),
`sortBy`, `drop`, `take`, `map`; after a `join` each
function takes a row of each table, and the query ends with a `map` that
names what it gives:

```
publicNotes : Db.Query (List { name : Str, body : Str })
publicNotes =
    notes
        |> Db.join people (fn note, person -> note.owner == person.id)
        |> Db.filter (fn note, _ -> note.public)
        |> Db.sortBy (fn note, _ -> note.body)
        |> Db.sortBy (fn _, person -> person.name)   -- by name, then by body
        |> Db.take 20
        |> Db.map (fn note, person -> { name = person.name, body = note.body })
        |> Db.all
```

A `leftJoin` keeps the rows that have no match: the joined row is a `Maybe`
(in its own condition it isn't). Take a column with `Maybe.map .name person`,
or test `person == Nothing`. A `groupBy` gives one row for each key, and the
`map` after it says what: the key, and aggregates of the rows. A `filter`
after the `groupBy` takes the key and the rows, and keeps groups (`HAVING`).
After a `join`, the key and the functions of the aggregates take a row of each
table.

```
allPublicNotes : Db.Query (List { name : Maybe Str, body : Str })
allPublicNotes =
    notes
        |> Db.leftJoin people (fn note, person -> note.owner == person.id)
        |> Db.filter (fn note, _ -> note.public)
        |> Db.map (fn note, person -> { name = Maybe.map .name person, body = note.body })
        |> Db.all

writers : Db.Query (List { owner : Str, count : Int, first : Str })
writers =
    notes
        |> Db.groupBy .owner
        |> Db.sortBy (fn owner, _ -> owner)
        |> Db.map (fn owner, rows -> { owner, count = Db.count rows, first = Db.min .body rows })
        |> Db.all

busyWriters : Db.Query (List { name : Str, count : Int, last : Str })
busyWriters =
    notes
        |> Db.join people (fn note, person -> note.owner == person.id)
        |> Db.groupBy (fn _, person -> person.name)
        |> Db.filter (fn _, rows -> Db.count rows >= 2)
        |> Db.map (fn name, rows -> { name, count = Db.count rows, last = Db.max (fn note, _ -> note.body) rows })
        |> Db.all
```

A transaction runs a function of queries on one connection: all of its
changes hold when it gives `Ok`, none when it gives `Err`. The queries in
`Db.transactionAs! user` run as that user (`Db.runAs! user`); transactions
don't nest.

```
pinOnly! = fn user, id ->
    _ = try Db.runAs! user (unpinAll user.id)
    count = try Db.runAs! user (pin id)
    if count == 0 then Err NotFound else Ok count

-- Db.transactionAs! user (fn _ -> pinOnly! user id)
```

Column types: `Str`, `Int`, `Float`, `Bool`, and `Maybe` of one of these
(a column that can be NULL; compare it with `== Nothing`). The functions of
`filter`, `map` and `update` are written in the query (`fn link -> ...`) and
use only the row's fields, values from outside the query (they become
parameters), `==`, `/=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, `not`, `+`, `-`,
`*` and `++`; anything else is P402: compute it before the query. A query
has at most one `map`, `take` and `drop`; `update` and `delete` only take
filters. A table's name is not a value: it only starts a query. For what the
query language can't do yet (subqueries, `UNION`, window functions), write the
SQL yourself with `Sql.query`:

### Postgres: SQL by hand

The database the wiring gives the app. A query is SQL written in the program
plus its parameters (`$1`, `$2`, ...); a row decoder reads the rows, as
`json.Decode` reads JSON. The SQL of `Sql.query` has to be a string literal
without `${...}` (rule P301): values always go in as parameters. The
compiler reads the SQL against the module's `table` declarations (P303): the
tables and columns must exist, a parameter has the type of the column it
meets (`created > $1` is `Sql.posix`, `LIMIT $1` is `Sql.int`), and the list
has exactly `$1` up to the last one.

```
import Platform.Postgres
import Platform.Sql
import Platform.Row

-- with `table links : Link` in the module; Link has url : Str and hits : Int
visitsRow : Row.Decoder Visits
visitsRow =
    Row.map2 (fn url, hits -> { url, hits })
        (Row.field "url" Row.text)
        (Row.field "hits" Row.int)

busiest : Int -> Sql.Query
busiest = fn n ->
    Sql.query "SELECT url, hits FROM links WHERE hits > 0 ORDER BY hits DESC LIMIT $1" [Sql.int n]

-- in an effect: visits = try Postgres.rows! visitsRow (busiest 10)
```

```
Sql.query : Str -> List Sql.Param -> Sql.Query      -- the Str must be a literal (P301)
Sql.text : Str -> Sql.Param                        -- also Sql.int (Int), Sql.float, Sql.bool, Sql.dec, Sql.json (text), Sql.null
Sql.nullable : (a -> Sql.Param) -> Maybe a -> Sql.Param
Row.field : Str -> Row.Column a -> Row.Decoder a   -- by column name
Row.int, Row.float, Row.text, Row.bool : Row.Column _   -- Row.nullable : Row.Column a -> Row.Column (Maybe a)
Row.posix, Row.uuid, Row.dec, Row.json (its text) : Row.Column _   -- Row.tryColumn Value.parse Row.json
Row.map, Row.map2 ... Row.map5, Row.succeed, Row.fail, Row.andThen
Postgres.rows! : Row.Decoder a -> Sql.Query => Result (List a) _
Postgres.row! : Row.Decoder a -> Sql.Query => Result (Maybe a) _      -- more than one row is a RowErr
Postgres.execute! : Sql.Query => Result U64 _                         -- the number of rows changed
-- errors: PgErr { code : Str, message : Str } (code is the SQLSTATE, "23505" = unique violation), RowErr Str
```

Columns are read as bool, int (`int2/4/8`), float (`float4/8`) or text
(`text`, `varchar`); convert anything else in the SQL (`created::text`,
`extract(epoch from t)::int8`). A parameter must have the type the query
expects (`Sql.int` for an `integer` column). Each query commits on its own:
there are no transactions yet.

### Mongo: documents

The document database the wiring gives the app; the wiring also says which
collections it may read or change. Documents are written with `Bson` (as
`Json.Encode`) and read with `Doc` decoders (as `Json.Decode`). Searches are
`Filter`s, changes `Update`s: the host writes Mongo's operators, a value is
always data, and collection and field names are string literals (P302).

```
import Platform.Mongo
import Platform.Bson
import Platform.Doc
import Platform.Filter
import Platform.Update

links : Mongo.Collection
links =
    Mongo.collection "links"

linkDecoder : Doc.Decoder Link
linkDecoder =
    Doc.map2 (fn url, created -> { url, created })
        (Doc.field "url" Doc.text)
        (Doc.field "created" Doc.int)

findLink! : Str => Result (Maybe Link) _
findLink! = fn id ->
    links
        |> Mongo.find (Filter.equals "_id" (Bson.text id))
        |> Mongo.first! linkDecoder
```

```
Mongo.collection : Str -> Mongo.Collection                 -- the Str must be a literal (P302)
Mongo.find : Filter -> Mongo.Collection -> Mongo.Find
Mongo.sortBy, Mongo.sortByDescending : Str -> Mongo.Find -> Mongo.Find   -- the last one decides first
Mongo.drop, Mongo.take : Int -> Mongo.Find -> Mongo.Find
Mongo.all! : Doc.Decoder a -> Mongo.Find => Result (List a) _
Mongo.first! : Doc.Decoder a -> Mongo.Find => Result (Maybe a) _
Mongo.count! : Mongo.Find => Result Int _
Mongo.insert! : Bson.Value -> Mongo.Collection => Result () _        -- a taken _id is code "11000"
Mongo.insertIfNew! : Bson.Value -> Mongo.Collection => Result Bool _ -- False when the _id is taken
Mongo.update! : Filter -> List Update -> Mongo.Collection => Result Int _   -- documents matched
Mongo.delete! : Filter -> Mongo.Collection => Result Int _
Filter.equals, notEquals, lessThan, atMost, greaterThan, atLeast : Str -> Bson.Value -> Filter
Filter.oneOf : Str -> List Bson.Value -> Filter    -- Filter.exists, Filter.missing : Str -> Filter
Filter.all, Filter.any : List Filter -> Filter     -- Filter.everything : Filter
Update.set : Str -> Bson.Value -> Update           -- Update.unset : Str -> Update, Update.increment : Str -> Int -> Update
Bson.text, Bson.int, Bson.float, Bson.bool, Bson.objectId (hex Str), Bson.time (ms Int) -- Bson.null
Bson.list : List Bson.Value -> Bson.Value          -- Bson.object : List (Str, Bson.Value) -> Bson.Value
Bson.nullable : (a -> Bson.Value) -> Maybe a -> Bson.Value
Doc.field : Str -> Doc.Decoder a -> Doc.Decoder a  -- Doc.optionalField : Str -> Doc.Decoder a -> Doc.Decoder (Maybe a)
Doc.text, Doc.int, Doc.float, Doc.bool, Doc.objectId, Doc.time : Doc.Decoder _
Doc.list, Doc.nullable, Doc.map ... Doc.map5, Doc.andThen, Doc.oneOf, Doc.succeed, Doc.fail, Doc.decode
-- errors: MongoErr { code : Str, message : Str } ("11000" duplicate key, "13" collection not allowed, "6" no server), DocErr Str
```

### JSON: the `json` package

Elm's `Json.Decode` and `Json.Encode`, as the modules `Decode` and `Encode`
of the package `json` that comes with punk (add `Json: "json"` to the app
header):

```
import Json.Decode as D
import Json.Encode as E

type alias Link = { url : Str, created : Int }

link : D.Decoder Link
link =
    D.map2 (fn url, created -> { url, created })
        (D.field "url" D.string)
        (D.field "created" D.int)

D.decodeString link text                    -- Result Link D.Error; D.errorToString for a message
E.encode 0 (E.object [("url", E.string l.url), ("created", E.int l.created)])
```

Decoders: `string int float dec bool null value list keyValuePairs field at index
maybe nullable oneOf succeed fail map map2 map3 map4 map5 andThen`. Encoders:
`string int float dec bool null list object dict`, and `E.encode indent value`.
There is no `andMap`: use `map2` to `map5`, or `andThen`. `Value` (`import
json.Value`) is the JSON tree; `Value.parse : Str -> Result Value Str`.
Do not compare a `Value` or a `D.Error` with `==` (the compiler hangs); compare
the encoded text instead.

### The tui platform

`platforms/tui` is for terminal apps (on ambit's tui platform), in the Elm
architecture. The app exposes its `Model` and `Msg` types and `main`:

```
app [Model, Msg, main] { Platform: platform "tui" }

import Platform.Tui
import Platform.Cmd
import Platform.Sub
import Platform.View
import Platform.File

type Msg
    = Loaded (Result Str Str)
    | Pressed Tui.Key

main = { init = init, update = update, view = view, subscriptions = subscriptions }

init : (Model, Cmd Msg)                            -- a value, not a function
init = ({ books = [] }, File.read "library.json" Loaded)

update : Msg -> Model -> (Model, Cmd Msg)
update = fn msg, model ->
    case msg of
        Pressed (Char "q") -> (model, Cmd.quit)
        Pressed Down -> ...
        Loaded (Ok text) -> ...
        _ -> (model, Cmd.none)

subscriptions : Model -> Sub Msg                   -- asked again after every update
subscriptions = fn _ -> Sub.onKey Pressed

view : Model -> View
```

```
Tui.Key = Char Str | Ctrl Str | Alt Str | Enter | Esc | Backspace | Delete | Tab | BackTab
        | Up | Down | Left | Right | Home | End | PageUp | PageDown | Insert | F Int
Cmd.none, Cmd.quit : Cmd msg
Cmd.batch : List (Cmd msg) -> Cmd msg
Cmd.after : Int -> msg -> Cmd msg                  -- milliseconds
Cmd.map : (a -> b) -> Cmd a -> Cmd b
Sub.none : Sub msg
Sub.batch : List (Sub msg) -> Sub msg
Sub.map : (a -> b) -> Sub a -> Sub b
Sub.onKey : (Tui.Key -> msg) -> Sub msg
Sub.onPaste : (Str -> msg) -> Sub msg
Sub.onResize : (Int -> Int -> msg) -> Sub msg   -- columns, rows: once at the start, then on a change
File.read : Str -> (Result Str Str -> msg) -> Cmd msg            -- only in the app's folder
File.list : Str -> (Result (List Str) Str -> msg) -> Cmd msg     -- "" is the folder; folders end in /
Clock.now : (Int -> msg) -> Cmd msg                -- milliseconds since 1970
Clock.every : Int -> (Int -> msg) -> Sub msg       -- every this many milliseconds, with the time
View.text : Str -> View                            -- lines of plain text
View.paragraph : List View.Line -> View            -- View.Line = List View.Span
View.list : Int -> List View.Line -> View          -- the line at this index highlighted, kept in sight
View.column, View.row : List View -> View          -- above / beside each other, sharing the room
View.height, View.width : Int -> View -> View      -- this many rows (in a column) / columns (in a row)
View.block : Str -> View -> View                   -- a frame with a title
View.empty : View
View.span : List View.Attr -> Str -> View.Span     -- View.span [View.bold, View.fg Yellow] "text"
View.plain : Str -> View.Span
View.bold, View.dim, View.italic, View.underline, View.reversed : View.Attr
View.fg, View.bg : View.Color -> View.Attr         -- Black Red Green Yellow Blue Magenta Cyan Gray DarkGray
                                                   -- LightRed ... LightCyan White
```

A tag with arguments is a function, as in Elm: `File.read path Loaded`.
Effects are commands: the app has no `!` functions; the platform does the
work off the screen's thread and answers with a `Msg`. Keys, pastes, the
terminal's size and timers come only through `subscriptions`: a key nothing
listens to doesn't reach `update`. Like a server, a
terminal app is not run with `punk app.punk`: a small Rust crate links it
and tests it on ambit's sim (see `platforms/tui/README.md` and
`examples/library/`). `compare` does not take `Str` (Roc's strings have
no order): compare `Str.toUtf8` bytes.

## Standard library

The functions an Elm or Roc programmer reaches for first. The value a
function works on is its last argument, so they fit `|>` and partial
application.

@@stdlib@@

## Cookbook

### Read a file given on the command line, solve, print

The shape of an Advent of Code solution: the example input in the file, the
real input from a file argument. (The cookbook files live in
`examples/aoc2024/`, hence their longer platform path; some use the
`test/fx/platform` test platform, which has `Stdout` too. Use
`platforms/cli` for your own programs.)

@@example aoc2024/Day01.punk@@

### A grid: `Dict (Int, Int) a`, neighbours, recursion

Written by an agent that had only this file, on the first try.

@@example aoc2024/Day10.punk@@

### Folds

@@example fold.punk@@

### Elm's names

@@example elm.punk@@

### Standard input and files

@@example platform/io.punk@@

### JSON decoders and encoders

@@example json/json.punk@@

### A server: ambit's link shortener

@@example shortener/Shortener.punk@@

### The same shortener with its links in Postgres

@@example shortener-postgres/Shortener.punk@@

### A terminal app

The smallest one; `examples/library/Library.punk` is crossload's
library view (sorting, marking, searching), with its tests on ambit's sim.

@@example counter/Counter.punk@@

## Style

Use `punk fmt` for layout and annotate top-level functions. The following
checks help a reader find the code that governs a behavior and follow it.

Use Elm's names where they exist, such as `List.filter`, `String.split`
and `Maybe`. Use `List.*` or `fold` for iteration, and return a `Result`
with meaningful error tags for recoverable failures.

### Organize modules around domain types

Keep a domain type with the operations that understand it. Expose the type
and the operations callers need. Qualify calls such as `Activity.encode` so
the reader can find them. Keep codec tests with the type. Give distinct wire
shapes distinct names, such as `decodeCreateInput` for a request body.

`Activity.punk` owns a type and an encoder and decoder for its JSON shape.

@@example activity-codec/Activity.punk@@

The app declares `Json: "json"` and imports `Activity`. Run `punk test` on
the app so the module's package imports resolve in the app's context.

### Make each step visible

Show the main steps of a successful operation at one indentation level.
Use a local name or a helper when it describes a meaningful step. Use a
`case` to keep distinct decisions visible, and `Result.map` and
`Result.mapError` for pure transformations of a result.

This version combines success and error handling with decoding and encoding
in one `case`.

```
normalize : Str -> Result Str Str
normalize = fn payload ->
    case D.decodeString Activity.decode payload of
        Ok activity -> Ok (E.encode 0 (Activity.encode activity))
        Err problem -> Err (D.errorToString problem)
```

The example app puts the transformations in a pipeline. Its `main!` reads
and writes, and its pure `normalize` function can be tested with a string.

@@example activity-codec/Demo.punk@@

In a server, keep routing, validation, query construction and response
encoding pure. Read the clock, generate IDs, run queries and log in the
handler or focused `!` helpers. Pass acquired values into pure functions
when it lets tests supply their own inputs. Keep the order of effects and
the start and end of a transaction easy to see. Prefer `try` when an error
should stop the whole operation and be handled by the caller.

### Lay out a multi-file server

For a small server, keep the punk sources in `src/` and the Rust host and
HTTP integration tests in `server/`. Sibling modules keep the paths short.
Start with modules that have a clear responsibility, then split further
when it helps explain what the app does. For example, an activity feed can
use this layout.

```text
src/
    Activities.punk  HTTP entry point, routing and table declarations
    Activity.punk    Activity type, validation and codecs
    JsonFields.punk  Shared JSON field checks
    schema.sql       Generated migrations
server/
    build.rs         Builds src/Activities.punk
    src/             Rust host and capability wiring
    tests/           HTTP integration tests
```

Keep `schema.sql` beside the app entry point. Model the storage row
separately when it differs from the domain or wire shape. A table can use a
local row alias or an exposed, storable record alias from another module.
If you move the app, update the entry point in `server/build.rs`, have Cargo
watch `src/` for source changes, and update where the host includes the schema.

```
punk fmt --check src/*.punk
punk check --json src/Activities.punk
punk test src/Activities.punk
punk check --schema src/Activities.punk
(cd server && cargo test)
```

Set `PUNK_TEST_POSTGRES` when running the Postgres specs.
`punk check --schema` can write a migration. After a style-only refactor,
check that it reports the schema is up to date and keep the HTTP behavior,
error mapping and effect order covered by the existing tests.

On v0.1.3, use lowercase `json.*` when importing the JSON package from a
sibling module and keep a table's row alias in the file that declares the
table. The codec example uses the current compiler's `Json.*` syntax.
