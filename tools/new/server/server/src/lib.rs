//! @App@, written in punk: `../@App@.punk` is the app, `../schema.sql` its tables.

use ambit_caps::{Clock, Random};
use ambit_server::Handler;
use punk_server::{BadSettings, Database, Settings};

/// The tables the app needs; the wiring applies them as the tables' owner.
pub const SCHEMA: &str = include_str!("../../schema.sql");

/// The names of the settings the app reads (its `settings` decoder in `../@App@.punk`). The wiring
/// takes these from the environment, and no others.
pub const SETTINGS: &[&str] = &[];

/// The app's capabilities: a clock, randomness, a database, and its settings.
pub fn init(
    clock: impl Clock,
    random: impl Random,
    database: impl Database,
    settings: Settings,
) -> Result<impl Handler, BadSettings> {
    Ok(punk_server::App::new(clock, random, NoKv, settings)?.with_database(database))
}

/// The key-value store of an app that has a database instead.
struct NoKv;

impl ambit_caps::Kv for NoKv {
    fn get(&self, _: &[u8]) -> Result<Option<Vec<u8>>, ambit_caps::KvError> {
        Err(no_kv())
    }
    fn put(&self, _: &[u8], _: &[u8]) -> Result<(), ambit_caps::KvError> {
        Err(no_kv())
    }
    fn delete(&self, _: &[u8]) -> Result<(), ambit_caps::KvError> {
        Err(no_kv())
    }
    fn scan(&self, _: &[u8]) -> Result<Vec<ambit_caps::Entry>, ambit_caps::KvError> {
        Err(no_kv())
    }
}

fn no_kv() -> ambit_caps::KvError {
    ambit_caps::KvError::new("this app has no key-value store")
}
