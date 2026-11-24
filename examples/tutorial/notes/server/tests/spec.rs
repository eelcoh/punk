// The notes API of the tutorial, over HTTP, on a real Postgres: each test gets its own schema
// of `PUNK_TEST_POSTGRES` with the app's table (`../schema.sql`), and the app connects as a
// role that keeps to its policies. Without a test database the tests say so and pass, unless
// `PUNK_REQUIRE_POSTGRES` is set (as in CI).

use std::time::{Duration, UNIX_EPOCH};

use ambit_server::Handler;
use ambit_server::http::StatusCode;
use ambit_server_sim::{SeededRandom, SimClock, request};
use punk_server::Settings;
use punk_server_postgres::{Owner, testing};

/// 2023-11-14 22:13:20 UTC, in milliseconds: the time of the notes the tests make.
const NOW: i64 = 1_700_000_000_000;

/// `NOW` as the JSON of a note has it.
const NOW_ISO: &str = "2023-11-14T22:13:20.000Z";

/// The API key of the tests: what `API_KEY` is set to.
const KEY: &str = "test-key-7f3a";

fn app(name: &str, schema: &str) -> Option<(impl Handler, Owner, SimClock)> {
    let (owner, db) = testing::database(&format!("notes_{name}"), schema)?;
    let clock = SimClock::at(UNIX_EPOCH + Duration::from_millis(NOW as u64));
    let settings = Settings::new().set("API_KEY", KEY);
    let app =
        notes::init(clock.clone(), SeededRandom::new(1), db, settings).expect("API_KEY is set");
    Some((app, owner, clock))
}

/// The request, with the API key.
fn send(app: &impl Handler, method: &str, uri: &str, body: &str) -> (StatusCode, String) {
    send_with(app, Some(&format!("Bearer {KEY}")), method, uri, body)
}

/// The request, with this `Authorization` header (or none).
fn send_with(
    app: &impl Handler,
    authorization: Option<&str>,
    method: &str,
    uri: &str,
    body: &str,
) -> (StatusCode, String) {
    let mut req = request(method, uri, body.as_bytes().to_vec());
    if let Some(value) = authorization {
        req.headers_mut()
            .insert("authorization", value.parse().unwrap());
    }
    let response = app.handle(req);
    let status = response.status();
    (status, String::from_utf8(response.into_body()).unwrap())
}

/// The id in a note's JSON: `{"id":"0190c3a5-...","title":...}`.
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
        format!(r#"{{"id":"{id}","title":"Shopping","body":"milk, bread","created":"{NOW_ISO}"}}"#)
    );
    // The id is a UUID (version 7: it starts with the time).
    assert_eq!(id.len(), 36, "{id}");
    assert_eq!(&id[14..15], "7", "{id}");
    assert!(id.starts_with(&format!("{NOW:012x}")[..8]), "{id}");
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
    // An id that isn't a UUID is no note either.
    assert_eq!(send(&app, "GET", "/notes/n1", "").0, StatusCode::NOT_FOUND);
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

#[test]
fn writing_needs_the_api_key() {
    let Some((app, _owner, _)) = app("key", notes::SCHEMA) else {
        return;
    };
    let note = r#"{"title": "Secret plan", "body": "none"}"#;
    for authorization in [None, Some("Bearer wrong"), Some(KEY), Some("Bearer ")] {
        let (status, json) = send_with(&app, authorization, "POST", "/notes", note);
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{authorization:?}");
        assert_eq!(json, r#"{"error":"this needs the API key"}"#);
    }
    let id = id_of(&create(&app, "Kept", "safe"));
    let uri = format!("/notes/{id}");
    assert_eq!(
        send_with(&app, None, "DELETE", &uri, "").0,
        StatusCode::UNAUTHORIZED
    );
    // Reading needs no key, and the note is still there.
    assert_eq!(send_with(&app, None, "GET", &uri, "").0, StatusCode::OK);
    assert_eq!(
        send_with(&app, None, "GET", "/notes", "").1,
        format!(r#"[{{"id":"{id}","title":"Kept","body":"safe","created":"{NOW_ISO}"}}]"#)
    );
}

#[test]
fn the_app_does_not_start_without_a_key() {
    let Some((_, db)) = testing::database("notes_nokey", notes::SCHEMA) else {
        return;
    };
    let db = std::sync::Arc::new(db);
    let clock = SimClock::at(UNIX_EPOCH);
    let Err(bad) = notes::init(
        clock.clone(),
        SeededRandom::new(1),
        db.clone(),
        Settings::new(),
    ) else {
        panic!("the app started without API_KEY");
    };
    assert_eq!(bad.problems, ["API_KEY is missing"]);
    let empty = Settings::new().set("API_KEY", "");
    let Err(bad) = notes::init(clock, SeededRandom::new(1), db, empty) else {
        panic!("the app started with an empty API_KEY");
    };
    assert_eq!(bad.problems, ["API_KEY is empty"]);
}

/// The migration of the tutorial: notes made before version 2 of `schema.sql` get `created`
/// `Time.millisToPosix 0`, 1970-01-01.
#[test]
fn the_migration_keeps_the_old_notes() {
    const OLD: &str = "0190c3a5-7b1e-7cc0-8a3b-2f1e7d6c5b4a";
    let version_1 = notes::SCHEMA.split("-- punk version 2").next().unwrap();
    let Some((app, owner, _)) = app("migrate", version_1) else {
        return;
    };
    owner
        .batch(&format!(
            "INSERT INTO notes (id, title, body) VALUES ('{OLD}', 'Before', 'version 1')"
        ))
        .unwrap();
    assert_eq!(owner.migrate(notes::SCHEMA).unwrap(), vec![2]);
    assert_eq!(
        send(&app, "GET", &format!("/notes/{OLD}"), ""),
        (
            StatusCode::OK,
            format!(
                r#"{{"id":"{OLD}","title":"Before","body":"version 1","created":"1970-01-01T00:00:00.000Z"}}"#
            )
        )
    );
}
