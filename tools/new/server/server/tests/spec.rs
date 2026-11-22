// @App@ over HTTP, on a real Postgres: each test gets its own schema of `PUNK_TEST_POSTGRES`
// (for example `postgres://localhost/@app@`) with the app's tables (`../schema.sql`), and the
// app connects as a role that keeps to their policies. Without a test database the tests say
// so and pass.

use std::time::{Duration, UNIX_EPOCH};

use ambit_server::Handler;
use ambit_server::http::StatusCode;
use ambit_server_sim::{SeededRandom, SimClock, request};
use punk_server_postgres::{Owner, testing};

fn setup(name: &str) -> Option<(impl Handler, Owner)> {
    let (owner, db) = testing::database(&format!("@crate@_{name}"), @crate@::SCHEMA)?;
    let clock = SimClock::at(UNIX_EPOCH + Duration::from_secs(1_700_000_000));
    Some((@crate@::init(clock, SeededRandom::new(1), db), owner))
}

fn send(app: &impl Handler, method: &str, uri: &str, body: &str) -> (StatusCode, String) {
    let response = app.handle(request(method, uri, body.as_bytes().to_vec()));
    let status = response.status();
    (status, String::from_utf8(response.into_body()).unwrap())
}

#[test]
fn hello() {
    let Some((app, _owner)) = setup("hello") else {
        return;
    };
    assert_eq!(
        send(&app, "GET", "/hello", ""),
        (StatusCode::OK, r#"{"hello":"world"}"#.to_owned())
    );
}

#[test]
fn an_unknown_path_is_not_found() {
    let Some((app, _owner)) = setup("unknown") else {
        return;
    };
    let (status, body) = send(&app, "GET", "/nothing", "");
    assert_eq!(
        (status, body.as_str()),
        (StatusCode::NOT_FOUND, r#"{"error":"not found"}"#)
    );
}
