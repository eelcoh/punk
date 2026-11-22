//! Wiring: which capabilities the punk app gets.
//!
//! The app connects with `DATABASE_URL` as a role that keeps to row-level security (no
//! superuser). Its tables and their policies are made at the start with `DATABASE_OWNER_URL`, a
//! role that owns them and lets the app's role use them; that is also when a new version of
//! `schema.sql` is applied (a migration). Without these settings it is the database `@app@` on
//! this computer: you own the tables, and the app is the role `@crate@_app`. On Linux the
//! server is then locked to its port and the database's port.

use ambit_lockdown::{Grant, Lockdown};
use ambit_server_native::{Listen, OsRandom, StdClock};
use punk_server_postgres::{Config, Owner, Postgres};

/// The settings without `DATABASE_URL` and `DATABASE_OWNER_URL`: Postgres on this computer.
const APP_URL: &str = "postgres://@crate@_app@localhost/@app@";
const OWNER_URL: &str = "postgres://localhost/@app@";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    ambit_server_native::init_tracing();

    let setting = |name: &str, default: &str| std::env::var(name).unwrap_or(default.to_owned());
    let url = setting("DATABASE_URL", APP_URL);
    let owner_url = setting("DATABASE_OWNER_URL", OWNER_URL);
    let port: u16 = setting("PORT", "8080").parse()?;

    let app_role = url
        .parse::<Config>()?
        .get_user()
        .ok_or("DATABASE_URL names no user")?
        .to_owned();
    let owner = Owner::connect(&owner_url)?;
    let applied = owner.migrate(@crate@::SCHEMA)?;
    for version in applied {
        tracing::info!("applied version {version} of schema.sql");
    }
    owner.grant(&app_role)?;
    drop(owner);

    let listen = Listen {
        addr: ([127, 0, 0, 1], port).into(),
        threads: 8,
        queue: 256,
    };
    let database = Postgres::new(&url, listen.threads)?;

    Lockdown::new()
        .allow(&database)
        .allow(&Grant::Listen(listen.addr.port()))
        .apply_or_warn("@app@")?;

    tracing::info!("@app@ listens on http://{}", listen.addr);
    let app = @crate@::init(StdClock::new(), OsRandom, database);
    ambit_server_native::serve(app, listen)?;
    Ok(())
}
