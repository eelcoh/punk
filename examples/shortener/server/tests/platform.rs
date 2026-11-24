//! What the punk platform adds to ambit's spec: the app frees what it allocates, and settings
//! that don't fit the app stop it before it serves a request.

use std::time::{Duration, UNIX_EPOCH};

use ambit_server::Handler;
use ambit_server::http::StatusCode;
use ambit_server_sim::{MemKv, SeededRandom, SimClock, get, post};

fn app() -> impl Handler {
    let clock = SimClock::at(UNIX_EPOCH + Duration::from_secs(1_700_000_000));
    let config = shortener::Config {
        base_url: "https://s.test/with/a/longer/prefix".into(),
        ttl: Duration::from_secs(60),
    };
    shortener::init(clock, SeededRandom::new(5), MemKv::new(), config)
}

#[test]
fn every_request_frees_what_it_allocates() {
    let app = app();
    let before = punk_server::thread_live_bytes();
    for i in 0..100 {
        let url = format!("https://example.com/a/page/with/a/long/enough/path/{i}");
        let created = app.handle(post("/links", url));
        assert_eq!(created.status(), StatusCode::CREATED);
        let short = String::from_utf8(created.into_body()).unwrap();
        let id = short.trim().rsplit('/').next().unwrap().to_owned();
        assert_eq!(
            app.handle(get(&format!("/{id}"))).status(),
            StatusCode::FOUND
        );
        assert_eq!(app.handle(get("/nothing")).status(), StatusCode::NOT_FOUND);
        assert_eq!(
            app.handle(post("/links", "ftp://x")).status(),
            StatusCode::BAD_REQUEST
        );
    }
    assert_eq!(punk_server::thread_live_bytes(), before);
}

#[test]
fn settings_that_dont_fit_stop_the_app() {
    let before = punk_server::thread_live_bytes();
    let settings = punk_server::Settings::new().set("TTL_SECONDS", "soon");
    let started = punk_server::App::new(
        SimClock::at(UNIX_EPOCH),
        SeededRandom::new(1),
        MemKv::new(),
        settings,
    );
    let Err(bad) = started else {
        panic!("the app started without BASE_URL");
    };
    assert_eq!(
        bad.problems,
        [
            "BASE_URL is missing",
            "TTL_SECONDS should be a whole number, it is \"soon\""
        ]
    );
    assert_eq!(punk_server::thread_live_bytes(), before);
}

#[test]
fn a_missing_setting_with_a_default_takes_the_default() {
    let settings = punk_server::Settings::new().set("BASE_URL", "https://s.test");
    let app = punk_server::App::new(
        SimClock::at(UNIX_EPOCH),
        SeededRandom::new(1),
        MemKv::new(),
        settings,
    )
    .expect("TTL_SECONDS has a default");
    let created = app.handle(post("/links", "https://example.com"));
    assert_eq!(created.status(), StatusCode::CREATED);
    assert!(
        String::from_utf8(created.into_body())
            .unwrap()
            .starts_with("https://s.test/")
    );
}
