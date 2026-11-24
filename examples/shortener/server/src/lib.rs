//! ambit's link shortener, written in punk: `../Shortener.punk` is the app, this crate gives it
//! the same Rust entry point as ambit's `apps/shortener`, so ambit's spec runs against it.
//!
//! - `POST /links` with a URL as body: creates a short link, `201` with the short URL.
//! - `GET /<id>`: `302` to the URL, `404` if unknown, `410` once expired.

use std::time::Duration;

use ambit_caps::{Clock, Kv, Random};
use ambit_server::Handler;

pub struct Config {
    /// Prefix for the short URLs this app hands out, e.g. `https://ambit.link`.
    pub base_url: String,
    /// How long a link stays valid.
    pub ttl: Duration,
}

/// The app's capabilities: this signature is everything it can do.
pub fn init(clock: impl Clock, random: impl Random, kv: impl Kv, config: Config) -> impl Handler {
    // What the punk app's `settings` decoder reads.
    let settings = punk_server::Settings::new()
        .set("BASE_URL", config.base_url)
        .set("TTL_SECONDS", config.ttl.as_secs().to_string());
    punk_server::App::new(clock, random, kv, settings)
        .expect("the settings are made from a `Config`, so they fit the app")
}
