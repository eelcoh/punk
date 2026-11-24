// The todo API, over HTTP, on a real Postgres: each test gets its own schema of
// `PUNK_TEST_POSTGRES` with the app's table (`../schema.sql`), and the app connects as a role
// that keeps to its policies. Without a test database the tests say so and pass, unless
// `PUNK_REQUIRE_POSTGRES` is set (as in CI).

use std::time::{Duration, UNIX_EPOCH};

use ambit_server::Handler;
use ambit_server::http::StatusCode;
use ambit_server_sim::{SeededRandom, SimClock, request};
use punk_server::Settings;
use punk_server_postgres::{Owner, testing};

fn setup(name: &str) -> Option<(impl Handler, Owner)> {
    let (owner, db) = testing::database(&format!("punk_todos_{name}"), todos::SCHEMA)?;
    let clock = SimClock::at(UNIX_EPOCH + Duration::from_secs(1_700_000_000));
    Some((
        todos::init(clock, SeededRandom::new(1), db, Settings::new())
            .expect("the app needs no settings"),
        owner,
    ))
}

fn send(app: &impl Handler, method: &str, uri: &str, body: &str) -> (StatusCode, String, String) {
    let response = app.handle(request(method, uri, body.as_bytes().to_vec()));
    let status = response.status();
    let content_type = response
        .headers()
        .get("content-type")
        .map(|v| v.to_str().unwrap().to_owned())
        .unwrap_or_default();
    (
        status,
        content_type,
        String::from_utf8(response.into_body()).unwrap(),
    )
}

/// The id in a todo's JSON: `{"id":"t123","title":...}`.
fn id_of(json: &str) -> String {
    let rest = json.strip_prefix(r#"{"id":""#).expect(json);
    rest[..rest.find('"').unwrap()].to_owned()
}

fn create(app: &impl Handler, title: &str) -> String {
    let (status, content_type, body) =
        send(app, "POST", "/todos", &format!(r#"{{"title": "{title}"}}"#));
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(content_type, "application/json");
    let id = id_of(&body);
    assert_eq!(
        body,
        format!(r#"{{"id":"{id}","title":"{title}","done":false}}"#)
    );
    id
}

#[test]
fn a_new_todo_can_be_read_back() {
    let Some((app, _owner)) = setup("create") else {
        return;
    };
    let id = create(&app, "buy milk");
    let (status, _, body) = send(&app, "GET", &format!("/todos/{id}"), "");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body,
        format!(r#"{{"id":"{id}","title":"buy milk","done":false}}"#)
    );
}

#[test]
fn the_list_is_a_json_array_by_title() {
    let Some((app, _owner)) = setup("list") else {
        return;
    };
    let (status, _, body) = send(&app, "GET", "/todos", "");
    assert_eq!((status, body.as_str()), (StatusCode::OK, "[]"));
    let walk = create(&app, "walk the dog");
    let milk = create(&app, "buy milk");
    let (status, _, body) = send(&app, "GET", "/todos", "");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body,
        format!(
            r#"[{{"id":"{milk}","title":"buy milk","done":false}},{{"id":"{walk}","title":"walk the dog","done":false}}]"#
        )
    );
}

#[test]
fn a_todo_can_be_changed() {
    let Some((app, _owner)) = setup("change") else {
        return;
    };
    let id = create(&app, "buy milk");
    let (status, _, body) = send(
        &app,
        "PUT",
        &format!("/todos/{id}"),
        r#"{"title": "buy oat milk", "done": true}"#,
    );
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body,
        format!(r#"{{"id":"{id}","title":"buy oat milk","done":true}}"#)
    );
    let (_, _, body) = send(&app, "GET", &format!("/todos/{id}"), "");
    assert_eq!(
        body,
        format!(r#"{{"id":"{id}","title":"buy oat milk","done":true}}"#)
    );
}

#[test]
fn a_todo_can_be_removed() {
    let Some((app, _owner)) = setup("remove") else {
        return;
    };
    let id = create(&app, "buy milk");
    let (status, _, body) = send(&app, "DELETE", &format!("/todos/{id}"), "");
    assert_eq!((status, body.as_str()), (StatusCode::NO_CONTENT, ""));
    let (status, _, body) = send(&app, "GET", &format!("/todos/{id}"), "");
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body, format!(r#"{{"error":"no todo {id}"}}"#));
    let (status, _, _) = send(&app, "DELETE", &format!("/todos/{id}"), "");
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[test]
fn bad_json_is_a_400_that_says_why() {
    let Some((app, _owner)) = setup("bad") else {
        return;
    };
    let (status, content_type, body) = send(&app, "POST", "/todos", r#"{"name": "buy milk"}"#);
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(content_type, "application/json");
    assert!(body.starts_with(r#"{"error":""#), "{body}");
    assert!(body.contains("title"), "{body}");
    let (status, _, _) = send(&app, "POST", "/todos", "not json");
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _, _) = send(&app, "PUT", "/todos/t1", r#"{"title": "x"}"#);
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[test]
fn unknown_routes_are_404() {
    let Some((app, _owner)) = setup("routes") else {
        return;
    };
    for (method, uri) in [("GET", "/"), ("PATCH", "/todos"), ("GET", "/todos/a/b")] {
        let (status, _, body) = send(&app, method, uri, "");
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {uri}");
        assert_eq!(body, r#"{"error":"not found"}"#);
    }
}
