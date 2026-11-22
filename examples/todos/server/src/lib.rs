//! A JSON API for a todo list, written in punk: `../Todos.punk` is the app, `../schema.sql` its
//! table. It is the example of the tutorial page "A JSON API with Postgres".
//!
//! - `GET /todos`: all todos, as a JSON array, by title.
//! - `POST /todos` with `{"title": "..."}`: a new todo, `201` with the todo.
//! - `GET /todos/<id>`: one todo, `404` if there is none.
//! - `PUT /todos/<id>` with `{"title": "...", "done": true}`: changes it.
//! - `DELETE /todos/<id>`: removes it, `204`.

use ambit_caps::{Clock, Random};
use ambit_server::Handler;
use punk_server::Database;

/// The table the app needs; the wiring applies it as the table's owner.
pub const SCHEMA: &str = include_str!("../../schema.sql");

/// The app's capabilities: randomness for the ids, and a database. The clock is not used.
pub fn init(clock: impl Clock, random: impl Random, database: impl Database) -> impl Handler {
    punk_server::App::new(clock, random, NoKv, "{}".to_owned()).with_database(database)
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
