//! Exercise the server ABI with a compiled app and in-memory capabilities.

use std::sync::{Arc, Mutex};
use std::time::UNIX_EPOCH;

use ambit_server_sim::{MemKv, SeededRandom, SimClock, get};
use punk_server::{
    App, Change, Comparison, Database, DbError, Doc, Documents, Filter, Handler, Order, Rows,
    Search, Settings, Value, thread_live_bytes,
};

fn app() -> App {
    App::new(
        SimClock::at(UNIX_EPOCH),
        SeededRandom::new(1),
        MemKv::new(),
        Settings::new(),
    )
    .unwrap()
}

fn assert_response(app: &App, path: &str, status: u16, body: &str) {
    let before = thread_live_bytes();
    let response = app.handle(get(path));
    assert_eq!(response.status().as_u16(), status, "{path}: {response:?}");
    assert_eq!(
        response.headers()["x-abi"],
        "a heap-allocated response header value"
    );
    assert_eq!(response.headers()["content-type"], "text/plain");
    assert_eq!(response.into_body(), body.as_bytes(), "{path}");
    assert_eq!(thread_live_bytes(), before, "allocations left after {path}");
}

struct SqlFixture {
    reply: Result<Rows, DbError>,
    calls: Mutex<Vec<(String, Vec<Value>)>>,
}

impl Database for SqlFixture {
    fn run(&self, sql: &str, params: &[Value]) -> Result<Rows, DbError> {
        self.calls
            .lock()
            .unwrap()
            .push((sql.to_owned(), params.to_vec()));
        self.reply.clone()
    }
}

#[test]
fn sql_parameters_rows_and_affected_count_cross_the_abi() {
    let input = "label=a-long-request-query-passed-as-a-SQL-parameter";
    let database = Arc::new(SqlFixture {
        reply: Ok(Rows {
            columns: vec!["amount".into(), "label".into()],
            rows: vec![
                vec![
                    Value::Int(-4_294_967_303),
                    Value::Text("a heap-allocated first row".into()),
                ],
                vec![Value::Int(17), Value::Text("second".into())],
            ],
            affected: 4_294_967_299,
        }),
        calls: Mutex::default(),
    });
    let app = app().with_database(database.clone());
    assert_response(
        &app,
        &format!("/sql/rows?{input}"),
        200,
        "a heap-allocated first row:-4294967303|second:17",
    );
    assert_response(&app, &format!("/sql/affected?{input}"), 200, "4294967299");

    let call = (
        "SELECT $1::text AS label, $2::bigint AS amount".into(),
        vec![Value::Text(input.into()), Value::Int(-4_294_967_297)],
    );
    assert_eq!(*database.calls.lock().unwrap(), [call.clone(), call]);
}

#[test]
fn sql_and_transaction_errors_preserve_code_and_message() {
    let app = app().with_database(SqlFixture {
        reply: Err(DbError::new("08001", "SQL error returned by the test host")),
        calls: Mutex::default(),
    });
    assert_response(
        &app,
        "/sql/rows",
        503,
        "08001:SQL error returned by the test host",
    );
    assert_response(
        &app,
        "/sql/transaction",
        503,
        "0A000:this database has no transactions",
    );
}

struct DocumentFixture {
    reply: Result<Vec<Doc>, DbError>,
    calls: Mutex<Vec<(String, Search)>>,
}

impl DocumentFixture {
    fn record(&self, collection: &str, search: &Search) {
        self.calls
            .lock()
            .unwrap()
            .push((collection.to_owned(), search.clone()));
    }
}

impl Documents for DocumentFixture {
    fn find(&self, collection: &str, search: &Search) -> Result<Vec<Doc>, DbError> {
        self.record(collection, search);
        self.reply.clone()
    }

    fn count(&self, collection: &str, search: &Search) -> Result<u64, DbError> {
        self.record(collection, search);
        self.reply
            .as_ref()
            .map(|_| 4_294_967_301)
            .map_err(Clone::clone)
    }

    fn insert(&self, _: &str, _: &Doc) -> Result<(), DbError> {
        Err(DbError::new("2", "unexpected insert"))
    }

    fn update(&self, _: &str, _: &Filter, _: &[Change]) -> Result<u64, DbError> {
        Err(DbError::new("2", "unexpected update"))
    }

    fn delete(&self, _: &str, _: &Filter) -> Result<u64, DbError> {
        Err(DbError::new("2", "unexpected delete"))
    }
}

#[test]
fn mongo_search_nested_document_and_count_cross_the_abi() {
    let input = "label=a-long-request-query-passed-as-a-filter-value";
    let documents = Arc::new(DocumentFixture {
        reply: Ok(vec![Doc::Object(vec![
            (
                "details".into(),
                Doc::Object(vec![(
                    "label".into(),
                    Doc::Text("a heap-allocated document label".into()),
                )]),
            ),
            ("amount".into(), Doc::Int(-4_294_967_309)),
        ])]),
        calls: Mutex::default(),
    });
    let app = app().with_documents(documents.clone());
    assert_response(
        &app,
        &format!("/mongo/documents?{input}"),
        200,
        "a heap-allocated document label:-4294967309",
    );
    assert_response(&app, &format!("/mongo/count?{input}"), 200, "4294967301");

    let call = (
        "abi_roundtrip".to_owned(),
        Search {
            filter: Filter::Compare {
                field: "label".into(),
                op: Comparison::Equals,
                value: Doc::Text(input.into()),
            },
            sort: vec![("amount".into(), Order::Descending)],
            skip: 3,
            limit: Some(5),
        },
    );
    let mut count_call = call.clone();
    count_call.1.sort.clear();
    assert_eq!(*documents.calls.lock().unwrap(), [call, count_call]);
}

#[test]
fn mongo_error_preserves_code_and_message() {
    let app = app().with_documents(DocumentFixture {
        reply: Err(DbError::new(
            "11600",
            "Mongo error returned by the test host",
        )),
        calls: Mutex::default(),
    });
    assert_response(
        &app,
        "/mongo/documents",
        503,
        "11600:Mongo error returned by the test host",
    );
}
