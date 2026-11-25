# punk's server platform

The platform for punk HTTP servers. Its host is written in Rust, on
[ambit](https://github.com/eelcoh/ambit)'s `server` platform and capabilities:
ambit owns the listener, the threads and the limits (body size, timeouts, a
full queue answers 503), and calls the punk app once per request.

```
app [Settings, main] { Platform: platform "server" }

import Platform.Http exposing [Request, Response]
import Platform.Config

main =
    { settings = settings, handle! = handle! }

type alias Settings =
    {}

settings : Config.Decoder Settings
settings =
    Config.succeed {}

handle! : Settings -> Request => Response
handle! = fn _, req ->
    case toRoute req of
        Just Hello -> { status = 200, headers = [], body = Str.toUtf8 "hello\n" }
        Nothing -> { status = 404, headers = [], body = [] }

type Route
    = Hello

toRoute : Request -> Maybe Route
toRoute = fn req ->
    case (Http.method req, Http.segments req) of
        (Get, ["hello"]) -> Just Hello
        _ -> Nothing

expect toRoute (Http.request Get "/hello") == Just Hello
```

| Module | Functions |
|--------|-----------|
| `Http` | the types `Request` (`method`, `path`, `query`, `headers`, `body : List U8`) and `Response` (`status : U16`, `headers`, `body : List U8`); for routing `method : Request -> Method` (`Get`, `Head`, `Post`, `Put`, `Patch`, `Delete`, `Options`, `Other Str`), `segments : Request -> List Str` (the parts of the path, percent-decoded), `header : Str -> Request -> Maybe Str` (a header, the name in any case), and `request : Method -> Str -> Request` for tests |
| `Kv` | `get! : Str => Result (Maybe Str) [KvErr Str]`, `put! key value`, `delete! key` (both `Result {} [KvErr Str]`) |
| `Clock` | `now! : () => I64` (milliseconds since 1970) |
| `Time` | as Elm's `Time`: the type `Posix` (a moment, in milliseconds since 1970 UTC), `now! : () => Posix`, `posixToMillis`, `millisToPosix`, `toIso8601 : Posix -> Str` (`"2026-11-24T12:14:20.123Z"`) and `fromIso8601 : Str -> Maybe Posix` (`Z` or an offset) |
| `Uuid` | the type `Uuid`: `generate! : () => Uuid` (version 7: ids made later sort later), `toString` (lowercase `8-4-4-4-12`), `fromString : Str -> Maybe Uuid` (either case, with or without dashes) |
| `Random` | `u64! : () => U64` |
| `Config` | decoders for the app's settings, as Elm's `Json.Decode`: `text "BASE_URL"`, `int`, `bool`, `secret`; `withDefault`, `maybe`; `map` to `map6`, `succeed`, `fail`, `andThen`; `decode decoder [("NAME", "value")]` for tests (see Settings below) |
| `Secret` | a password, key or token, from `Config.secret`: it can't become text (`Str.inspect` shows `<secret>`). `matches : Str -> Secret -> Bool` compares in constant time; `fromText` for tests |
| `Log` | `info!`, `warn!`, `error! : Str => {}` |
| `Postgres` | `rows! : Row.Decoder a -> Sql.Query => Result (List a) _`, `row!` (at most one row: `Maybe a`), `execute! : Sql.Query => Result U64 _` (rows changed) |
| `Sql` | `query : Str -> List Sql.Param -> Sql.Query` (the SQL is a literal, rule P301), parameters `text`, `int`, `float`, `bool`, `posix`, `uuid`, `dec`, `json` (JSON text), `null`, `nullable` |
| `Db` | the query language: `table` declarations and pipelines (`links \|> Db.filter f \|> Db.first`), `run! : Db.Query a => Result a _`, `toSql` |
| `Row` | decoders as Elm's `Json.Decode`: `field "url" Row.text`, columns `int`, `float`, `text`, `bool`, `posix`, `uuid`, `dec`, `json` (its text), `nullable`, `mapColumn`, `tryColumn` (`Row.tryColumn Value.parse Row.json`); `map` to `map5`, `succeed`, `fail`, `andThen` |
| `Mongo` | `collection "links"`, searches `find filter`, `sortBy`, `sortByDescending`, `drop`, `take`, run with `all! decoder`, `first! decoder`, `count!`; `insert! document`, `insertIfNew!`, `update! filter changes`, `delete! filter` |
| `Bson` | values for documents, as Elm's `Json.Encode`: `text`, `int`, `float`, `bool`, `null`, `nullable`, `list`, `object [("url", Bson.text url)]`, `objectId`, `time` (a `Posix`) |
| `Doc` | decoders for documents, as Elm's `Json.Decode`: `field "url" Doc.text`, `optionalField`, `int`, `float`, `text`, `bool`, `objectId`, `time` (a `Posix`), `list`, `nullable`, `map` to `map5`, `andThen`, `oneOf`, `succeed`, `fail`, `decode` |
| `Filter` | `equals`, `notEquals`, `lessThan`, `atMost`, `greaterThan`, `atLeast`, `oneOf`, `exists`, `missing` (each `"field" value`), `all [..]`, `any [..]`, `everything` |
| `Update` | `set "field" value`, `unset "field"`, `increment "field" n` |

The example app is ambit's link shortener: `examples/shortener/`, and
the same app with its links in Postgres: `examples/shortener-postgres/`,
and in Mongo: `examples/shortener-mongo/`.

## Postgres: tables and queries

A table is declared in punk, with the type of its rows, its key and who may
do what with its rows. Queries are pipelines from the table, as in Acadia;
punk compiles each one to one SQL statement with parameters (no ORM, no
N+1), and the rows to the query's type:

```
import Platform.Db

type alias Link =
    { id : Str
    , url : Str
    , created : Int
    }

table links : Link
    key id
    read everyone
    insert everyone
    update nobody
    delete nobody

findLink : Str -> Db.Query (Maybe Link)
findLink = fn id ->
    links
        |> Db.filter (fn link -> link.id == id)
        |> Db.first

-- SELECT id, url, created FROM links WHERE id = $1 LIMIT 1
```

- **Steps.** In this order: `Db.join users (fn l, u -> l.owner == u.id)`
  or `Db.leftJoin`, `Db.filter` (several are joined with AND), `Db.groupBy`,
  `Db.sortBy` and
  `Db.sortByDescending` (the last one decides first, as with `List.sortBy`),
  `Db.drop n` (`OFFSET`), `Db.take n` (`LIMIT`) and at most one `Db.map`
  (`.url`, or a record `{ url = l.url, later = l.created + 10 }`), then one
  of `Db.all`, `Db.first`, `Db.update (fn l -> { l | url = new })` or
  `Db.delete` (these two take only filters). After a join each function
  takes a row of each table (`fn link, user -> ...`), the query is still one
  statement (`FROM links t0 JOIN users t1 ON ...`), and it ends in a `map`
  that names what it gives. `Db.insert row links` and `Db.insertIfNew row links` (`ON
  CONFLICT DO NOTHING`) add a row. `Db.run!` runs a `Db.Query a`; the
  changing ones give the number of rows changed. `Db.runAs! user query`
  runs it as the user, for the tables whose policies look at the user.
- **Left joins and groups.** After `Db.leftJoin people (fn n, p -> ...)`
  the person is a `Maybe` (`LEFT JOIN`): take a column with
  `Maybe.map .name p`, or test `p == Nothing` (`IS NULL`). After
  `Db.groupBy .owner` the functions take the key and the rows of a group
  (`GROUP BY`), and the `map` names what each group gives:
  `Db.map (fn owner, rows -> { owner, n = Db.count rows, total = Db.sum .amount rows })`,
  with `Db.count`, `Db.sum`, `Db.min`, `Db.max` and `Db.avg`. Grouping works
  on one table for now.
- **Column types.** A column is a `Str`, `Int`, `Float`, `Bool`, `Posix`
  (`Time`), `Uuid`, `Dec` or `Value` (JSON, from the `json` package), or a
  `Maybe` of one when it can be empty. A type of
  the program with one tag that holds one of these is a column too, and
  the right one for ids:

  ```
  type LinkId = LinkId Uuid

  type alias Link =
      { id : LinkId
      , owner : UserId
      , created : Posix
      }
  ```

  The database stores what it holds (`uuid`), so wrapping a column in a
  type of its own needs no migration; in queries it only meets values of
  its own type (`link.id == LinkId "x"`, not `link.id == "x"`, P403), so an
  owner can't be taken for a link. A `Posix` column can be compared and
  sorted on in a query; in a migration or policy a constant time is
  `Time.millisToPosix 0`.

  A `Dec` is an exact decimal (`numeric`), for money and the like: sums and
  averages of it stay `Dec`, and it reads and writes JSON with `D.dec` and
  `E.dec`. A `Value` is JSON as it came (`jsonb`), for data whose shape the
  table doesn't fix: it needs `import Json.Value` next to the table, a query
  only tests it against `Nothing` (it has no order or equality in SQL), and
  you decode it after the query with `D.decodeValue`. Postgres keeps `jsonb`
  objects with their keys in its own order (shorter keys first).
- **Checked by the compiler, without a database.** A column the table
  doesn't have, a literal of the wrong type and a comparison of a `Str` with
  an `Int` are errors with a code (P403); a function the database can't run
  (your own function, `String.startsWith`) is P402. A value from outside the
  query becomes a parameter typed by the column it meets (`Db.param_text`),
  so Roc's type checker catches a variable of the wrong type.
- **A policy per table, kept by the database.** A table says who may read,
  insert, update and delete; without all four it doesn't compile (P401), and
  a query that does what a `nobody` forbids is P404. A policy is `everyone`,
  `nobody`, or a function of the user and the row:

  ```
  table notes : Note
      key id
      read fn user, note -> note.public || note.owner == user.id
      insert fn user, note -> note.owner == user.id
      update fn user, note -> note.owner == user.id
      delete nobody
  ```

  Each becomes a Postgres row-level security policy (`ENABLE` and `FORCE
  ROW LEVEL SECURITY`, `CREATE POLICY ... USING (owner = <the user>)`), so the
  database keeps to it for every query, also SQL by hand. `nobody` gets no
  policy, so no row. The fields of the user go to the database as settings
  of the query's transaction (`punk.user_id`); `Db.runAs! user query` gives
  them, `Db.run!` gives none, and then a policy that compares with the user
  is not true. A row a policy refuses to insert or keep is error `42501`.
  The fields of the user get their type from the column they meet.
- **A role that keeps to the policies.** The app connects as a role of its
  own: `Postgres::new` refuses a superuser or a role with `BYPASSRLS`, which
  skip row-level security. The wiring makes the tables with `Owner` (a role
  that owns them) and lets the app's role use them with `Owner::grant`;
  `examples/notes` shows it, and `punk_server_postgres::testing` sets
  up both roles for tests.
- **Tables in a module of their own.** A module can declare tables and
  expose them like values; a module that imports it starts queries from
  them as from its own:

  ```
  module Tables exposing (UserId(..), Note, notes)

  table notes : Note
      ...

  -- in the app
  import Tables exposing (UserId(..), Note, notes)

  readable = notes |> Db.all          -- or Tables.notes
  ```

  The app's `schema.sql` holds every table of the program: its own and
  those of the modules it imports, at any depth. So the app checks them
  (P405) and `punk check --schema app.punk` writes their versions; a
  `migrate` stays next to the table it migrates, in the module, and an
  error about it points at the import. `examples/notes` keeps its tables in
  `Tables.punk`.
- **The schema comes from the program, with verified migrations.**
  `schema.sql` next to the app is a history of versions, which `punk check
  --schema app.punk` writes (`Str` is `text`, `Int` `bigint`, `Float`
  `double precision`, `Bool` `boolean`, `Posix` `timestamptz`, `Uuid`
  `uuid`, `Dec` `numeric`, `Value` `jsonb`, `Maybe` nullable, the key `PRIMARY KEY`). Each version records the tables as they were. When the tables in
  the program differ from the last version, the program doesn't compile
  (P405) until `punk check --schema` has added a version. A new table, a new
  `Maybe` column or a new policy needs nothing else; any other change of a
  table needs a migration, a function from the old row to the new one:

  ```
  migrate notes
      fn old -> { old | body = old.text, pinned = False }
  ```

  `body = old.text` is a rename; another value (`False`, `old.created +
  10`, the same expressions as in a query, without values from outside) is
  computed in the database for the rows there are; an old column the new row
  doesn't take is dropped. `punk check --schema` says what the new version
  does. Once it is in `schema.sql`, remove the `migrate` (P405 says so). The
  wiring applies the versions with `Owner::migrate`: each once, in order, in a
  transaction of its own, recorded in the table `punk_schema`; a version that
  changed after it was applied is an error. `examples/notes` has two
  versions.

  A table with a new name says where it came from, with a function below it
  when its columns change too; a table that goes, with its rows, says so:

  ```
  migrate links from urls
  remove table visits
  ```

  `migrate links from urls` is `ALTER TABLE urls RENAME TO links` (its
  policies get the new name). A table that is gone from the program without
  either line doesn't compile, so a rename never drops the rows by accident.
  Both lines go once the version is in `schema.sql`.
- **Transactions.** `Db.transaction! (fn _ -> ...)` runs a function of
  queries in one transaction, on one connection: `Ok` commits it, `Err`
  rolls it back. `Db.transactionAs! user (fn _ -> ...)` gives it the fields
  of the user, and its queries run as that user (`Db.runAs! user`; a query
  as someone else is error `25000`). Transactions don't nest (`25001`), and
  one the app leaves open rolls back at the end of the request. In the host
  it is `Database::begin`, which gives a `Transaction` (`run`, `commit`;
  dropping it rolls back). `examples/notes` pins one note per user this
  way.
- **SQL by hand stays.** For what the language can't do yet (grouping a
  join, `HAVING`, subqueries), `Sql.query` and `Row` below are the escape hatch.

## Postgres: SQL by hand

```
import Platform.Postgres
import Platform.Sql
import Platform.Row

type alias Link =
    { id : Str
    , url : Str
    , hits : Int
    }

table links : Link
    key id
    read everyone
    insert everyone
    update everyone
    delete nobody

type alias Visits = { url : Str, hits : Int }

visitsRow : Row.Decoder Visits
visitsRow =
    Row.map2 (fn url, hits -> { url, hits })
        (Row.field "url" Row.text)
        (Row.field "hits" Row.int)

busiest : Int -> Sql.Query
busiest = fn n ->
    Sql.query "SELECT url, hits FROM links WHERE hits > 0 ORDER BY hits DESC LIMIT $1" [Sql.int n]

top! : Int => Result (List Visits) _
top! = fn n ->
    Postgres.rows! visitsRow (busiest n)
```

- **No SQL from text.** A `Sql.Query` is SQL written in the program plus the
  values for its parameters. `Sql.Query` is opaque, so only `Sql.query` makes
  one, and punk only accepts a string literal without `${...}` as its SQL
  (rule P301): `Sql.query ("SELECT * FROM " ++ table) []` doesn't compile. A
  value from a request can only ever be a parameter.
- **Checked against the tables (P303).** The compiler reads the SQL against
  the module's `table` declarations, without a database: every table it
  names is declared (`table links : Link`), every column is one of theirs
  (`l.url`, or a bare `url` that only one table has), each parameter has the
  `Sql` type of the column it is compared with or goes into
  (`created > $1` wants `Sql.posix`, `INSERT INTO links (id, hits) VALUES
  ($1, $2)` wants `Sql.text` and `Sql.int`, `LIMIT $1` an `Sql.int`), a
  `Sql.null` only goes into a `Maybe` column, and the list gives exactly
  `$1` up to the last parameter. Columns of a `WITH` or a subquery, and a
  parameter with a cast (`$1::text`), are left to Postgres, which checks
  them when it prepares the query.
- **Typed both ways.** The host prepares the SQL and checks each parameter
  against the type the statement wants (`Sql.int` for an `integer`, an `Int`
  that doesn't fit an `int4` is an error, not a wrapped number). A column is
  read as bool, int (`int2/4/8`), float (`float4/8`), text (`text`,
  `varchar`, `char`, `name`), time (`timestamptz`, `timestamp` as UTC) or
  uuid; for any other type the error says how to
  convert it in the SQL (`created::text`). The decoder then checks each
  column's kind, so a row that doesn't fit is `RowErr "column \"created\":
  expected an int, got text"`, not a wrong value.
- **Errors are values.** `PgErr { code, message }` has Postgres's SQLSTATE
  (`23505` is a unique violation, `08000` is no connection); the shortener
  answers 503 for it and 500 for a `RowErr`.
- **A capability.** The wiring opens the database and hands it to the app
  (`App::with_database`); the app never sees the connection string, and an
  app without one gets `PgErr { code = "08000", .. }` for every query.
- **What the query language makes.** A `Db.Query` is exactly such a
  `Sql.Query` and a `Row.Decoder`, made by the compiler from the table's
  type (`platforms/server/Db.roc`).

The database itself is the crate `postgres/` (`punk-server-postgres`), for
the wiring on Linux and macOS:

```rust
let owner = punk_server_postgres::Owner::connect(&std::env::var("DATABASE_OWNER_URL")?)?;
owner.migrate(include_str!("../../schema.sql"))?;     // the app's tables, at their last version
owner.grant("app")?;                                   // the app's role may use them
drop(owner);
let database = punk_server_postgres::Postgres::new(&std::env::var("DATABASE_URL")?, 8)?;
Lockdown::new().allow(&database) ...                   // its port (and the resolver for a name)
let app = punk_server::App::new(clock, random, kv, settings)?.with_database(database);
```

**TLS.** The connection string decides, as with libpq: `sslmode=disable`,
`prefer` or `require` (also `verify-ca` and `verify-full`). Without
`sslmode` a database on this machine (`localhost`, a loopback address, a
Unix socket) is `disable` (nothing crosses a network), and any other is
`require`: a connection over a network is not quietly without TLS. With TLS the server's certificate is
always checked, for its host name, also with `require` (where libpq checks
nothing): against Mozilla's list of authorities (built in, so it works in an
image without `/etc/ssl`), or only the authorities in the PEM file
`sslrootcert=<file>` names (a cloud's own, or yours). The file is read when
the pool is made, before the lockdown.

It is a pool of at most `max` connections: a query takes a free one, or
opens one, or waits up to 5 seconds (then `PgErr { code = "53300" }`). A
broken connection is dropped and the next query opens a new one, so the app
recovers by itself when the database comes back. Each connection prepares a
statement once and keeps it. `options=-c statement_timeout=5s` in the
connection string limits how long a query may take.

## Mongo

Documents in collections, written and read as Elm writes and reads JSON:

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
    Doc.map3 (fn id, url, created -> { id, url, created })
        (Doc.field "_id" Doc.text)
        (Doc.field "url" Doc.text)
        (Doc.field "created" Doc.int)

linkDocument : Link -> Bson.Value
linkDocument = fn link ->
    Bson.object
        [ ("_id", Bson.text link.id)
        , ("url", Bson.text link.url)
        , ("created", Bson.int link.created)
        ]

recent! : Int => Result (List Link) _
recent! = fn since ->
    links
        |> Mongo.find (Filter.atLeast "created" (Bson.int since))
        |> Mongo.sortByDescending "created"
        |> Mongo.take 20
        |> Mongo.all! linkDecoder

visit! : Str => Result Int _
visit! = fn id ->
    Mongo.update! (Filter.equals "_id" (Bson.text id)) [Update.increment "visits" 1] links
```

- **No query from text, no operator from a value.** A Mongo query is a
  document in which keys like `$ne` and `$where` are operators, so a value
  from a request that is an object (`{"$ne": ""}`) can turn a lookup into
  "any document": the classic NoSQL injection. Here the app never writes a
  query document. `Filter` and `Update` say what to compare and change, and
  the host writes the operators (`$eq`, `$in`, `$set`, `$inc`, ...) itself,
  with the value as data under `$eq`. A key that starts with `$` is refused
  anywhere in a value (error "2"), and there is no `$where` or other
  JavaScript.
- **Names in the program.** The name of a collection (`Mongo.collection`)
  and of a field (`Filter.*`, `Update.*`, `Mongo.sortBy`) is a string
  literal, not empty and not starting with `$` (rule P302), as the SQL of
  `Sql.query` is (P301): a request can't choose which collection a query
  reads or which field it compares. `"address.city"` names a field of an
  object in the document.
- **Typed both ways.** A `Bson.Value` is made only by `Bson`'s functions; an
  `Int` is stored as an int64, a `time` as Mongo's date. A decoder checks
  each field it reads (int32 and int64 are both `Doc.int`), so a document
  that doesn't fit is `DocErr "document 1: field \"created\": expected an
  int, got text"`, not a wrong value. A missing field is an error, unless the
  decoder says `Doc.optionalField`; a type punk doesn't read (a binary, a
  decimal) is an error that says so.
- **Errors are values.** `MongoErr { code, message }` has Mongo's error code
  as text: "11000" is a duplicate key, "121" a document the collection's
  validator refuses, "13" a collection the app may not use, "6" no server.
  `Mongo.insertIfNew!` gives `False` instead of "11000". The shortener
  answers 503 for a `MongoErr` and 500 for a `DocErr`.
- **The collections are a capability.** The wiring says which collections
  the app may read and which it may change; any other is "13", whatever the
  database user may do. An app without a document database gets "6" for
  everything.

The database is the crate `mongo/` (`punk-server-mongo`, on the official
driver), for the wiring on Linux and macOS:

```rust
use punk_server_mongo::{Access, Mongo};

let mongo = Mongo::connect(&std::env::var("MONGO_URL")?, "shortener")?
    .allow("links", Access::ReadWrite);               // and no other collection
Lockdown::new().allow(&mongo) ...                     // its port (and the resolver for a name)
let app = punk_server::App::new(clock, random, kv, settings)?.with_documents(mongo);
```

**TLS** as the connection string says: `tls=true`, and `tlsCAFile=<file.pem>`
for an authority of the database's own (`mongodb+srv://` has TLS by itself).
Without `tls`, a server that isn't on this machine gets TLS anyway; `tls=false`
says it may go without, for a private network. The certificate is checked
against Mozilla's list (built in), or only the authorities in `tlsCAFile`.

The driver keeps a pool of connections and reconnects by itself; an
operation that finds no server within 5 seconds is "6" (set
`serverSelectionTimeoutMS` in the connection string for another limit).
`Mongo::unique_index` makes a unique index for the wiring; `_id` always has
one. Tests use `punk_server_mongo::testing::database` (a fresh database on
`PUNK_TEST_MONGO`).

## Settings and secrets

An app says which settings it needs, and what type each one is, with a
decoder in Elm's style; the platform hands `handle!` the result:

```
app [Settings, main] { Platform: platform "server" }

import Platform.Http exposing [Request, Response]
import Platform.Config
import Platform.Secret

main =
    { settings = settings, handle! = handle! }

type alias Settings =
    { baseUrl : Str
    , ttlSeconds : Int
    , apiKey : Secret
    }

settings : Config.Decoder Settings
settings =
    Config.map3 (fn baseUrl, ttlSeconds, apiKey -> { baseUrl, ttlSeconds, apiKey })
        (Config.text "BASE_URL")
        (Config.int "TTL_SECONDS" |> Config.withDefault 3600)
        (Config.secret "API_KEY")

handle! : Settings -> Request => Response
handle! = fn config, req -> ...
```

The wiring gives the settings as names with text, `punk_server::Settings`,
usually from environment variables it names one by one:

```rust
let settings = punk_server::Settings::from_env(&["BASE_URL", "TTL_SECONDS", "API_KEY"]);
let app = punk_server::App::new(clock, random, kv, settings)?;
```

`App::new` runs the decoder once, before the server starts: settings that
don't fit are a `BadSettings` with one line per setting (`API_KEY is
missing`, `TTL_SECONDS should be a whole number, it is "soon"`), so a server
with a typo in its settings never takes a request. A secret's value is never
in such a message, and `Settings`' `Debug` shows only the names. For each
request the decoder runs again, on that request's thread (a value made by
the app is never shared between threads); that takes microseconds.

A `Secret` has no way back to text: there is no `Secret.toText`, `Log.info!`
takes a `Str`, and `Str.inspect` and `dbg` show `<secret>`. An app can only
compare a value with it (`Secret.matches token config.apiKey`, every byte, so
the time says nothing about where they differ) or, later, hand it to the
platform (a JWT signing key, J4).

## What the app can do

Only what the platform hands it, as in ambit: a clock, randomness, one
key-value store, one SQL database, one document database (the collections
the wiring allows), its settings and a log. There is no file, network,
process or environment access in the API, so a punk server app can't reach
anything else, whatever its code does. Which store, which clock and which
settings is up to the wiring, a few lines of Rust per app (like ambit's
`run-native`): the real ones in its `main`, the deterministic ones of
`ambit-server-sim` in its tests. The wiring of the shortener also locks the
whole process to its database file and its port (ambit's `Lockdown`: Landlock
and seccomp on Linux).

The response goes through the host before it is sent: a status outside 100 to
999 or a header name or value HTTP can't carry (a line break, for instance)
turns the response into a 500, so request data can't smuggle a header in. The
app never sees the connection.

A crash of the app (only possible through a bug: punk rejects `crash` outside
tests, P101) stops the server: it can't unwind through compiled punk, and
whatever runs the server starts it again.

## Building and testing an app

A server app isn't run with `punk app.punk`. `punk build` compiles it into an
archive (`output: Archive` in `main.roc`), and a small Rust crate next to the
app links that archive with this host and is the program:

```
examples/shortener/
    Shortener.punk          the app
    server/
        Cargo.toml          depends on platforms/server/host and ambit
        build.rs            runs `punk build` on Shortener.punk, links libapp.a
        src/lib.rs          init(clock, random, kv, config): the app as an ambit Handler, with its settings
        src/main.rs         the wiring: native store, clock, randomness, lockdown, port
        src/hermit.rs       the wiring as a Hermit unikernel (ambit's hermit backend)
        tests/spec.rs       ambit's spec/tests/shortener.rs, copied unchanged
        acceptance.sh       ambit's black-box HTTP tests, native or hermit
```

```
zig build
cd examples/shortener/server
cargo test                  # ambit's spec, against the punk app
cargo run --release         # http://localhost:8080
```

`build.rs` uses `zig-out/bin/punk` of this repository, or the compiler named
by the `PUNK` environment variable.

### As a unikernel

The same app runs as a [Hermit](https://hermit-os.org) unikernel, on ambit's
hermit backend. For `x86_64-unknown-hermit`, `build.rs` compiles the app for
`x64v1elf` (freestanding x86-64 at the baseline CPU level: Hermit's QEMU CPU
model has no AVX), and `src/hermit.rs` does the wiring as ambit's
`run-hermit` does: an in-memory store (links are lost when the VM stops),
the hardware random generator, and port 8080 over virtio-net.

```
cargo build --release --target x86_64-unknown-hermit   # a 1.8 MB image
./acceptance.sh hermit      # boots it in QEMU and runs ambit's HTTP tests
```

Setup (the Rust std for Hermit, QEMU, the loader) as in
`platforms/cli/hermit/README.md`. Nothing has to be locked down: the image is
the whole machine, and the only way in is the port.

An app with Postgres runs as a unikernel too: `punk new server` writes
`server/src/hermit.rs` (the same wiring as `main.rs`, with the settings from
the kernel's command line) and `server/unikernel.sh`, which adds the Rust std
for Hermit when it isn't there, builds the image and boots it in QEMU, against
Postgres on the same computer (10.0.2.2 in QEMU's network) or the URLs in
`DATABASE_URL` and `DATABASE_OWNER_URL`. The Postgres driver and TLS need four
crates with a few changes for Hermit: `hermit/` has them, and why.
`test/hermit.sh` boots the tutorial's notes API that way and tries it over
HTTP (the `hermit` job of CI).

### As a container

`punk new server` writes a `Dockerfile` next to the app: a build on
`rust:<version>-slim-trixie` that installs the punk-lang release (checked
against its SHA256SUMS) and runs `cargo build --release` for
`<arch>-unknown-linux-musl`, and an image of only that static program on
`gcr.io/distroless/static-debian12:nonroot` (about 11 MB), with `HOST=0.0.0.0`.
The database runs elsewhere; the wiring reads `DATABASE_URL` and
`DATABASE_OWNER_URL`, with TLS as above. `docs/tutorial` (In a container) walks
through it. `--build-arg PUNK_ARCHIVE=<archive in the folder>` builds with a
punk that isn't released (from `tools/release/package.sh`).

## How the host fits together

```
 Shortener.punk ─ punk build ─▶ libapp.a       (the app: no I/O of its own)
                                  │  calls roc_alloc, roc_kv_get, roc_clock_now, ...
                                  ▼  is called as roc_handle, once per request
 host/ (Rust, crate punk-server)  App: ambit_server::Handler
                                  │
 server/ (the app's crate) ─────▶ init(...) -> impl Handler; main(): ambit_server_native::serve
```

- `main.roc` and the other `.roc` files: the platform's API, what a punk app
  sees. `hosted { ... }` maps each effect to the C symbol the host exports.
- `host/src/lib.rs`: `App`, the punk app as an ambit `Handler`; the exported
  runtime functions and effects. Each request runs on one thread from start to
  end; the effects find the request's capabilities in a thread-local.
- `../roc-abi`: Roc's `Str`, `List` and `Try`, and the allocator, shared with
  the cli platform.

After each request the host checks that the app freed everything it
allocated for it, and logs a warning when not (`tests/platform.rs` of the
shortener checks it too).

## Not there yet

- The query language: grouping a join, filtering groups (`HAVING`).
- On hermit: `sslrootcert` (a unikernel has no files) and a test of host
  names (DNS); see `hermit/README.md`. Certificates for the app itself
  (`sslcert`, `tlsCertificateKeyFile`).
- Times, UUIDs, JSON and `numeric` as their own types: convert them in the
  SQL for now.

- Mongo: transactions (they need a replica set), aggregation pipelines
  (grouping, `$lookup`), indexes declared in punk instead of the wiring,
  Mongo on hermit (the driver needs tokio), and schema validators made
  from the decoders.
- `Kv.scan` (ambit has it): no app needed it yet.
- A store that survives a restart on hermit (ambit has none there yet either).
