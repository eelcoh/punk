// The notes API of the tutorial, over HTTP, on a real Postgres: each test gets its own schema
// of `PUNK_TEST_POSTGRES` with the app's table (`../schema.sql`), and the app connects as a
// role that keeps to its policies. Without a test database the tests say so and pass, unless
// `PUNK_REQUIRE_POSTGRES` is set (as in CI).

use std::time::{Duration, UNIX_EPOCH};

use ambit_server::Handler;
use ambit_server::http::StatusCode;
use ambit_server_sim::{SeededRandom, SimClock, request};
use punk_server_postgres::{Owner, testing};

/// 2023-11-14 22:13:20 UTC, in milliseconds: the time of the notes the tests make.
const NOW: i64 = 1_700_000_000_000;

fn app(name: &str, schema: &str) -> Option<(impl Handler, Owner, SimClock)> {
    let (owner, db) = testing::database(&format!("notes_{name}"), schema)?;
    let clock = SimClock::at(UNIX_EPOCH + Duration::from_millis(NOW as u64));
    let app = notes::init(clock.clone(), SeededRandom::new(1), db);
    Some((app, owner, clock))
}

fn send(app: &impl Handler, method: &str, uri: &str, body: &str) -> (StatusCode, String) {
    let response = app.handle(request(method, uri, body.as_bytes().to_vec()));
    let status = response.status();
    (status, String::from_utf8(response.into_body()).unwrap())
}

/// The id in a note's JSON: `{"id":"n123","title":...}`.
fn id_of(json: &str) -> String {
    let rest = json.strip_prefix(r#"{"id":""#).expect(json);
    rest[..rest.find('"').unwrap()].to_owned()
}

fn create(app: &impl Handler, title: &str, body: &str) -> String {
    let (status, json) = send(
        app,
        "POST",
        "/notes",
        &format!(r#"{{"title": "{title}", "body": "{body}"}}"#),
    );
    assert_eq!(status, StatusCode::CREATED, "{json}");
    json
}

#[test]
fn a_new_note_can_be_read_back() {
    let Some((app, _owner, _)) = app("create", notes::SCHEMA) else {
        return;
    };
    let json = create(&app, "Shopping", "milk, bread");
    let id = id_of(&json);
    assert_eq!(
        json,
        format!(r#"{{"id":"{id}","title":"Shopping","body":"milk, bread","created":{NOW}}}"#)
    );
    assert_eq!(
        send(&app, "GET", &format!("/notes/{id}"), ""),
        (StatusCode::OK, json)
    );
}

#[test]
fn the_list_is_newest_first() {
    let Some((app, _owner, clock)) = app("list", notes::SCHEMA) else {
        return;
    };
    assert_eq!(
        send(&app, "GET", "/notes", ""),
        (StatusCode::OK, "[]".to_owned())
    );
    let old = create(&app, "Old", "first");
    clock.advance(Duration::from_secs(60));
    let new = create(&app, "New", "second");
    assert_eq!(
        send(&app, "GET", "/notes", ""),
        (StatusCode::OK, format!("[{new},{old}]"))
    );
}

#[test]
fn a_note_can_be_deleted_once() {
    let Some((app, _owner, _)) = app("delete", notes::SCHEMA) else {
        return;
    };
    let id = id_of(&create(&app, "Gone", "soon"));
    let uri = format!("/notes/{id}");
    assert_eq!(send(&app, "DELETE", &uri, "").0, StatusCode::NO_CONTENT);
    assert_eq!(send(&app, "GET", &uri, "").0, StatusCode::NOT_FOUND);
    assert_eq!(send(&app, "DELETE", &uri, "").0, StatusCode::NOT_FOUND);
}

#[test]
fn a_bad_body_is_a_400_that_says_why() {
    let Some((app, _owner, _)) = app("bad", notes::SCHEMA) else {
        return;
    };
    let (status, json) = send(&app, "POST", "/notes", r#"{"title": "no body"}"#);
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.starts_with(r#"{"error":"#), "{json}");
}

/// The migration of the tutorial: notes made before version 2 of `schema.sql` get `created` 0.
#[test]
fn the_migration_keeps_the_old_notes() {
    let version_1 = notes::SCHEMA.split("-- punk version 2").next().unwrap();
    let Some((app, owner, _)) = app("migrate", version_1) else {
        return;
    };
    owner
        .batch("INSERT INTO notes (id, title, body) VALUES ('n1', 'Before', 'version 1')")
        .unwrap();
    assert_eq!(owner.migrate(notes::SCHEMA).unwrap(), vec![2]);
    assert_eq!(
        send(&app, "GET", "/notes/n1", ""),
        (
            StatusCode::OK,
            r#"{"id":"n1","title":"Before","body":"version 1","created":0}"#.to_owned()
        )
    );
}
