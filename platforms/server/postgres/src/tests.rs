//! Against a real database: `PUNK_TEST_POSTGRES` is its connection string (CI starts one). Without
//! it the tests say so and pass, unless `PUNK_REQUIRE_POSTGRES` is set (as in CI).

use super::*;

/// A pool on a fresh schema of the test database with these tables, or `None` when there is no
/// database.
fn pool(name: &str, tables: &str) -> Option<Postgres> {
    testing::database(&format!("punk_pool_{name}"), tables).map(|(_, db)| db)
}

#[test]
fn parameters_and_columns_have_their_types() {
    let Some(db) = pool(
        "types",
        "CREATE TABLE t (s smallint, i integer, b bigint, r real, d double precision, t text, v varchar(10), f bool, n text)",
    ) else {
        return;
    };
    let insert = "INSERT INTO t VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)";
    let params = [
        Value::Int(-3),
        Value::Int(70_000),
        Value::Int(i64::MAX),
        Value::Float(0.5),
        Value::Float(0.1),
        Value::Text("hé \"quoted\"".into()),
        Value::Text("short".into()),
        Value::Bool(true),
        Value::Null,
    ];
    assert_eq!(db.run(insert, &params).unwrap().affected, 1);
    let rows = db.run("SELECT * FROM t", &[]).unwrap();
    assert_eq!(rows.columns, ["s", "i", "b", "r", "d", "t", "v", "f", "n"]);
    assert_eq!(rows.rows, vec![params.to_vec()]);
    assert_eq!(rows.affected, 1);
}

#[test]
fn times_and_uuids_have_their_types() {
    let Some(db) = pool(
        "time_uuid",
        "CREATE TABLE t (at timestamptz, local timestamp, id uuid)",
    ) else {
        return;
    };
    let params = [
        Value::Time(1_764_000_000_123),
        Value::Time(-1),
        Value::Uuid(*b"0123456789abcdef"),
    ];
    db.run("INSERT INTO t VALUES ($1, $2, $3)", &params)
        .unwrap();
    let rows = db.run("SELECT * FROM t", &[]).unwrap();
    assert_eq!(rows.rows, vec![params.to_vec()]);
    // What Postgres makes itself reads the same way.
    let rows = db
        .run(
            "SELECT '2026-11-24T12:00:00.0015Z'::timestamptz AS at, '30313233-3435-3637-3839-616263646566'::uuid AS id",
            &[],
        )
        .unwrap();
    assert_eq!(
        rows.rows,
        vec![vec![
            Value::Time(1_795_521_600_001),
            Value::Uuid(*b"0123456789abcdef")
        ]]
    );
    // Text is not a UUID.
    let e = db
        .run("SELECT * FROM t WHERE id = $1", &[Value::Text("x".into())])
        .unwrap_err();
    assert_eq!(e.code, "42804");
}

#[test]
fn json_and_numeric_have_their_types() {
    let Some(db) = pool(
        "json_numeric",
        "CREATE TABLE t (j jsonb, k json, n numeric, m numeric(10, 2))",
    ) else {
        return;
    };
    let cases = [
        ("0", "0.00"),
        ("-12.5", "-12.50"),
        ("12345678.000123", "12345678.00"),
        ("0.0001", "0.00"),
        ("10000", "10000.00"),
        ("-0.05", "-0.05"),
    ];
    for (n, m) in cases {
        db.run("DELETE FROM t", &[]).unwrap();
        let params = [
            Value::Json(r#"{"a": [1, null]}"#.into()),
            Value::Json(r#"{"b" : true}"#.into()),
            Value::Dec(n.into()),
            Value::Dec(n.into()),
        ];
        db.run("INSERT INTO t VALUES ($1, $2, $3, $4)", &params)
            .unwrap();
        let rows = db.run("SELECT * FROM t", &[]).unwrap();
        assert_eq!(
            rows.rows,
            vec![vec![
                Value::Json(r#"{"a": [1, null]}"#.into()),
                Value::Json(r#"{"b" : true}"#.into()),
                Value::Dec(n.into()),
                Value::Dec(m.into()),
            ]],
            "{n}"
        );
        // Postgres's own text of the number is the same.
        let text = db.run("SELECT n::text AS n FROM t", &[]).unwrap();
        assert_eq!(text.rows, vec![vec![Value::Text(n.into())]]);
    }
    let rows = db.run("SELECT 'NaN'::numeric AS n", &[]).unwrap_err();
    assert!(rows.message.contains("NaN"), "{}", rows.message);
}

#[test]
fn a_wrong_parameter_type_says_what_to_do() {
    let Some(db) = pool("wrong_param", "CREATE TABLE t (n integer)") else {
        return;
    };
    let e = db
        .run("INSERT INTO t VALUES ($1)", &[Value::Text("7".into())])
        .unwrap_err();
    assert_eq!(e.code, "42804");
    assert!(e.message.contains("parameter $1 is int4"), "{}", e.message);
    let e = db
        .run("INSERT INTO t VALUES ($1)", &[Value::Int(1 << 40)])
        .unwrap_err();
    assert_eq!(e.code, "22003");
    let e = db.run("INSERT INTO t VALUES ($1)", &[]).unwrap_err();
    assert_eq!(e.code, "08P01");
}

#[test]
fn an_unknown_column_type_says_how_to_convert_it() {
    let Some(db) = pool("column_type", "") else {
        return;
    };
    let e = db.run("SELECT now()::date AS created", &[]).unwrap_err();
    assert_eq!(e.code, "0A000");
    assert!(e.message.contains("created::text"), "{}", e.message);
    let rows = db
        .run("SELECT extract(epoch from now())::int8 AS created", &[])
        .unwrap();
    assert!(matches!(rows.rows[0][0], Value::Int(n) if n > 1_700_000_000));
}

#[test]
fn errors_carry_the_sqlstate() {
    let Some(db) = pool("errors", "CREATE TABLE t (id text PRIMARY KEY)") else {
        return;
    };
    db.run("INSERT INTO t VALUES ($1)", &[Value::Text("a".into())])
        .unwrap();
    let e = db
        .run("INSERT INTO t VALUES ($1)", &[Value::Text("a".into())])
        .unwrap_err();
    assert_eq!(e.code, "23505");
    assert_eq!(db.run("SELEC 1", &[]).unwrap_err().code, "42601");
    // The connection is still good after an error.
    assert_eq!(
        db.run("SELECT 1 AS one", &[]).unwrap().rows,
        vec![vec![Value::Int(1)]]
    );
}

#[test]
fn the_pool_shares_its_connections() {
    let Some(db) = pool("threads", "CREATE TABLE t (n bigint)") else {
        return;
    };
    let db = std::sync::Arc::new(db);
    let threads: Vec<_> = (0..8)
        .map(|i| {
            let db = db.clone();
            std::thread::spawn(move || {
                for j in 0..20 {
                    db.run("INSERT INTO t VALUES ($1)", &[Value::Int(i * 100 + j)])
                        .unwrap();
                }
            })
        })
        .collect();
    for t in threads {
        t.join().unwrap();
    }
    let rows = db.run("SELECT count(*) AS n FROM t", &[]).unwrap();
    assert_eq!(rows.rows, vec![vec![Value::Int(160)]]);
    assert!(db.pool.state.lock().unwrap().open <= 2);
}

#[test]
fn no_database_is_an_error_not_a_hang() {
    let db = Postgres::new("host=127.0.0.1 port=1 user=nobody connect_timeout=2", 1).unwrap();
    let e = db.run("SELECT 1", &[]).unwrap_err();
    assert_eq!(e.code, "08000");
    // The failed connection gave its place back.
    assert_eq!(db.pool.state.lock().unwrap().open, 0);
}

#[test]
fn grants_name_the_port_and_the_resolver() {
    let db = Postgres::new("postgres://app@db.internal:6543/links", 1).unwrap();
    assert_eq!(db.grants(), vec![Grant::Connect(6543), Grant::Resolve]);
    let db = Postgres::new("host=127.0.0.1 user=app", 1).unwrap();
    assert_eq!(db.grants(), vec![Grant::Connect(5432)]);
}

/// A table with policies as punk makes them: everyone reads the public notes and their own,
/// and writes only their own.
const NOTES: &str = "
    CREATE TABLE notes (id text PRIMARY KEY, owner text NOT NULL, public boolean NOT NULL);
    ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
    ALTER TABLE notes FORCE ROW LEVEL SECURITY;
    CREATE POLICY notes_read ON notes FOR SELECT USING (public OR owner = NULLIF(current_setting('punk.user_id', true), ''));
    CREATE POLICY notes_insert ON notes FOR INSERT WITH CHECK (owner = NULLIF(current_setting('punk.user_id', true), ''));
    INSERT INTO notes VALUES ('a1', 'ann', false), ('a2', 'ann', true), ('b1', 'bob', false);
";

fn as_user(id: &str) -> Vec<(String, String)> {
    vec![("punk.user_id".to_owned(), id.to_owned())]
}

fn ids(db: &Postgres, settings: &[(String, String)]) -> Vec<Value> {
    let rows = db
        .run_as(settings, "SELECT id FROM notes ORDER BY id", &[])
        .unwrap();
    rows.rows.into_iter().map(|mut r| r.remove(0)).collect()
}

fn text(s: &str) -> Value {
    Value::Text(s.to_owned())
}

#[test]
fn policies_see_the_user_of_the_query() {
    let Some(db) = pool("policies", NOTES) else {
        return;
    };
    assert_eq!(ids(&db, &as_user("ann")), [text("a1"), text("a2")]);
    assert_eq!(ids(&db, &as_user("bob")), [text("a2"), text("b1")]);
    // Without a user, only what is public; the setting of the last query is gone.
    assert_eq!(ids(&db, &[]), [text("a2")]);
    // Bob can't write a note of Ann's: the insert policy refuses it, and nothing is written.
    let e = db
        .run_as(
            &as_user("bob"),
            "INSERT INTO notes VALUES ('x', 'ann', false)",
            &[],
        )
        .unwrap_err();
    assert_eq!(e.code, "42501");
    assert_eq!(
        db.run_as(
            &as_user("bob"),
            "INSERT INTO notes VALUES ('b2', 'bob', false)",
            &[]
        )
        .unwrap()
        .affected,
        1
    );
    // There is no update policy: no row can be changed.
    let rows = db
        .run_as(&as_user("ann"), "UPDATE notes SET public = true", &[])
        .unwrap();
    assert_eq!(rows.affected, 0);
}

#[test]
fn a_failed_query_as_a_user_leaves_the_connection_good() {
    let Some(db) = pool("rollback", NOTES) else {
        return;
    };
    assert!(db.run_as(&as_user("ann"), "SELEC 1", &[]).is_err());
    assert_eq!(ids(&db, &[]), [text("a2")]);
    assert_eq!(ids(&db, &as_user("bob")), [text("a2"), text("b1")]);
}

#[test]
fn a_transaction_commits_all_or_rolls_back_all() {
    let Some(db) = pool("transaction", NOTES) else {
        return;
    };
    // Its queries see each other's changes, and run as its user.
    let mut tx = db.begin(&as_user("bob")).unwrap();
    tx.run("INSERT INTO notes VALUES ('b2', 'bob', false)", &[])
        .unwrap();
    let rows = tx.run("SELECT count(*) FROM notes", &[]).unwrap();
    assert_eq!(rows.rows, vec![vec![Value::Int(3)]]);
    // Others don't, until it commits.
    assert_eq!(ids(&db, &as_user("bob")), [text("a2"), text("b1")]);
    tx.commit().unwrap();
    assert_eq!(
        ids(&db, &as_user("bob")),
        [text("a2"), text("b1"), text("b2")]
    );
    // Dropped without a commit, nothing of it holds, also after a failed query.
    let mut tx = db.begin(&as_user("bob")).unwrap();
    tx.run("INSERT INTO notes VALUES ('b3', 'bob', false)", &[])
        .unwrap();
    assert!(tx.run("SELEC 1", &[]).is_err());
    drop(tx);
    let mut tx = db.begin(&as_user("bob")).unwrap();
    tx.run("INSERT INTO notes VALUES ('b4', 'bob', false)", &[])
        .unwrap();
    drop(tx);
    assert_eq!(
        ids(&db, &as_user("bob")),
        [text("a2"), text("b1"), text("b2")]
    );
    // The settings end with the transaction.
    assert_eq!(ids(&db, &[]), [text("a2")]);
}

#[test]
fn a_transaction_gives_its_connection_back() {
    let Some(db) = pool("transaction_pool", NOTES) else {
        return;
    };
    // The test pool has 2 connections: many transactions after another don't use them up.
    for _ in 0..5 {
        let tx = db.begin(&as_user("ann")).unwrap();
        drop(tx);
        db.begin(&[]).unwrap().commit().unwrap();
    }
    assert_eq!(ids(&db, &as_user("ann")), [text("a1"), text("a2")]);
    let e = db
        .begin(&[("search_path".to_owned(), "x".to_owned())])
        .err()
        .unwrap();
    assert_eq!(e.code, "42602");
}

#[test]
fn only_punk_settings_can_be_given() {
    let Some(db) = pool("settings", NOTES) else {
        return;
    };
    let e = db
        .run_as(
            &[("role".to_owned(), "postgres".to_owned())],
            "SELECT 1 AS one",
            &[],
        )
        .unwrap_err();
    assert_eq!(e.code, "42602");
}

#[test]
fn a_role_that_skips_row_level_security_is_refused() {
    let Ok(url) = std::env::var("PUNK_TEST_POSTGRES") else {
        return;
    };
    // The test database's own role is a superuser.
    let db = Postgres::new(&url, 1).unwrap();
    let e = db.run("SELECT 1 AS one", &[]).unwrap_err();
    assert_eq!(e.code, "42501");
    assert!(e.message.contains("row-level security"), "{}", e.message);
    assert_eq!(db.pool.state.lock().unwrap().open, 0);
}

const V1: &str = "-- made by punk

-- punk version 1
CREATE TABLE t (id text PRIMARY KEY, n bigint NOT NULL);
";

const V2: &str = "
-- punk version 2
ALTER TABLE t ADD COLUMN m bigint;
UPDATE t SET m = n * 2;
ALTER TABLE t ALTER COLUMN m SET NOT NULL;
";

/// An owner of a fresh schema, with nothing in it.
fn owner(name: &str) -> Option<(Owner, Postgres)> {
    testing::database(&format!("punk_migrate_{name}"), "")
}

#[test]
fn migrate_applies_each_version_once() {
    let Some((owner, db)) = owner("once") else {
        return;
    };
    assert_eq!(owner.migrate(V1).unwrap(), [1]);
    assert_eq!(owner.migrate(V1).unwrap(), Vec::<u32>::new());
    owner.grant(testing::APP_ROLE).unwrap();
    db.run("INSERT INTO t VALUES ('a', 21)", &[]).unwrap();
    // A new version keeps the rows, and computes the new column for them.
    assert_eq!(owner.migrate(&format!("{V1}{V2}")).unwrap(), [2]);
    let rows = db.run("SELECT m FROM t", &[]).unwrap();
    assert_eq!(rows.rows, vec![vec![Value::Int(42)]]);
    assert_eq!(
        owner.migrate(&format!("{V1}{V2}")).unwrap(),
        Vec::<u32>::new()
    );
}

#[test]
fn migrate_refuses_a_version_that_changed() {
    let Some((owner, _)) = owner("changed") else {
        return;
    };
    owner.migrate(V1).unwrap();
    let e = owner.migrate(&V1.replace("bigint", "integer")).unwrap_err();
    assert_eq!(e.code, "P0405");
    assert!(e.message.contains("version 1"), "{}", e.message);
    // The comment before the first version is no part of it.
    assert!(
        owner
            .migrate(&V1.replace("made by", "made with"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn a_failed_version_changes_nothing() {
    let Some((owner, _)) = owner("failed") else {
        return;
    };
    owner.migrate(V1).unwrap();
    let broken = "\n-- punk version 2\nALTER TABLE t ADD COLUMN m bigint;\nALTER TABLE nothing ADD COLUMN x bigint;\n";
    assert!(owner.migrate(&format!("{V1}{broken}")).is_err());
    // Version 2 was not applied, nor any part of it.
    assert_eq!(owner.migrate(&format!("{V1}{V2}")).unwrap(), [2]);
}

#[test]
fn versions_count_up_from_one() {
    let Some((owner, _)) = owner("count") else {
        return;
    };
    assert_eq!(
        owner
            .migrate("CREATE TABLE t (n bigint);")
            .unwrap_err()
            .code,
        "P0405"
    );
    assert_eq!(owner.migrate(V2).unwrap_err().code, "P0405");
}

/// TLS against `PUNK_TEST_POSTGRES_TLS`: a server with TLS whose certificate is signed by the
/// authority in `PUNK_TEST_POSTGRES_CA` (a PEM file), for the host name of the URL. Without them
/// the test says so and passes.
#[test]
fn tls_checks_the_servers_certificate() {
    let (Ok(url), Ok(ca)) = (
        std::env::var("PUNK_TEST_POSTGRES_TLS"),
        std::env::var("PUNK_TEST_POSTGRES_CA"),
    ) else {
        eprintln!("no PUNK_TEST_POSTGRES_TLS and PUNK_TEST_POSTGRES_CA: skipping tls");
        return;
    };
    let separator = if url.contains('?') { "&" } else { "?" };
    let with = |options: &str| format!("{url}{separator}{options}");
    // Whether the connection of a pool (as the app's role, which keeps to row-level security)
    // has TLS.
    let ssl = |options: &str| {
        let tls::Settings { mut config, tls } = tls::settings(&with(options))?;
        if config.get_dbname().is_none() {
            let dbname = config.get_user().unwrap_or("postgres").to_owned();
            config.dbname(&dbname);
        }
        config.user(testing::APP_ROLE).password("punk");
        let db = Postgres::with_tls(config, tls, 1);
        let rows = db.run(
            "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()",
            &[],
        )?;
        Ok::<_, DbError>(rows.rows[0][0].clone())
    };
    let setup = Owner::connect(&with(&format!("sslrootcert={ca}"))).unwrap();
    setup
        .batch(&format!(
            "DO $$ BEGIN
                 CREATE ROLE {} LOGIN PASSWORD 'punk';
             EXCEPTION WHEN duplicate_object OR unique_violation THEN NULL;
             END $$;",
            testing::APP_ROLE
        ))
        .unwrap();

    // With the authority that signed it: TLS, also when only preferred.
    for mode in ["require", "verify-ca", "verify-full", "prefer"] {
        let got = ssl(&format!("sslmode={mode}&sslrootcert={ca}"));
        assert_eq!(got.unwrap(), Value::Bool(true), "sslmode={mode}");
    }

    // With Mozilla's list the test authority is unknown: no connection, and the error says why.
    for mode in ["require", "prefer"] {
        let e = ssl(&format!("sslmode={mode}")).unwrap_err();
        assert_eq!(e.code, "08000");
        assert!(e.message.contains("sslrootcert"), "{}", e.message);
        assert!(Owner::connect(&with(&format!("sslmode={mode}"))).is_err());
    }

    // Without TLS when the connection string says so.
    assert_eq!(ssl("sslmode=disable").unwrap(), Value::Bool(false));
}

#[test]
fn a_schema_without_tables_has_no_versions() {
    let new_app = include_str!("../../../../tools/new/server/schema.sql");
    assert_eq!(versions(new_app).unwrap(), vec![]);
    assert_eq!(
        versions("CREATE TABLE t (x int);").unwrap_err().code,
        "P0405"
    );
}

#[test]
fn statement_timeout_defaults_and_clamping() {
    assert_eq!(statement_timeout_ms(Duration::ZERO), 0);
    assert_eq!(statement_timeout_ms(Duration::from_micros(500)), 1);
    assert_eq!(statement_timeout_ms(Duration::from_millis(250)), 250);
    assert_eq!(statement_timeout_ms(Duration::from_secs(30)), 30_000);
    assert_eq!(
        statement_timeout_ms(Duration::from_secs(u64::MAX)),
        i32::MAX as u64
    );

    let db = Postgres::new("postgres://app@localhost/db", 2).unwrap();
    assert_eq!(db.pool.statement_timeout, Some(DEFAULT_STATEMENT_TIMEOUT));

    let custom = db.with_statement_timeout(Some(Duration::from_secs(5)));
    assert_eq!(custom.pool.statement_timeout, Some(Duration::from_secs(5)));

    let disabled = custom.with_statement_timeout(None);
    assert_eq!(disabled.pool.statement_timeout, None);

    let from_url = Postgres::new(
        "postgres://app@localhost/db?options=-c%20statement_timeout%3D1234",
        2,
    )
    .unwrap();
    assert_eq!(from_url.pool.statement_timeout, None);
}

#[test]
fn slow_query_hits_statement_timeout_and_keeps_connection_usable() {
    let Some(db) = pool("timeout", "") else {
        return;
    };
    let db = db.with_statement_timeout(Some(Duration::from_millis(50)));
    let err = db.run("SELECT pg_sleep(1)", &[]).unwrap_err();
    assert_eq!(err.code, "57014", "expected query_canceled, got: {err:?}");
    let rows = db.run("SELECT 1", &[]).unwrap();
    assert_eq!(rows.rows, vec![vec![Value::Int(1)]]);
}
