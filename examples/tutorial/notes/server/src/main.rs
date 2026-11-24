//! Wiring: which capabilities the punk app gets.
//!
//! The app connects with `DATABASE_URL` as a role that keeps to row-level security (no
//! superuser). Its tables and their policies are made at the start with `DATABASE_OWNER_URL`, a
//! role that owns them and lets the app's role use them; that is also when a new version of
//! `schema.sql` is applied (a migration). Without these settings it is the database `notes` on
//! this computer: you own the tables, and the app is the role `notes_app`. A database that
//! isn't on this computer gets TLS (`sslmode` and `sslrootcert` in the URLs say otherwise). The
//! server listens on `HOST` (default 127.0.0.1, this computer only; the container's is 0.0.0.0)
//! and `PORT` (8080). On Linux the server is then locked to its port and the database's port.
//!
//! The app's own settings are the environment variables that `SETTINGS` in `lib.rs` names, and
//! no others; the server doesn't start when they don't fit the app's `settings` decoder.
//!
//! As a Hermit unikernel the wiring is `hermit.rs` instead.

#[cfg(target_os = "hermit")]
mod hermit;

#[cfg(target_os = "hermit")]
use hermit::main;

#[cfg(not(target_os = "hermit"))]
use ambit_lockdown::{Grant, Lockdown};
#[cfg(not(target_os = "hermit"))]
use ambit_server_native::{Listen, OsRandom, StdClock};
#[cfg(not(target_os = "hermit"))]
use punk_server::Settings;
#[cfg(not(target_os = "hermit"))]
use punk_server_postgres::{Owner, Postgres};

/// The settings without `DATABASE_URL` and `DATABASE_OWNER_URL`: Postgres on this computer.
#[cfg(not(target_os = "hermit"))]
const APP_URL: &str = "postgres://notes_app@localhost/notes";
#[cfg(not(target_os = "hermit"))]
const OWNER_URL: &str = "postgres://localhost/notes";

#[cfg(not(target_os = "hermit"))]
fn main() -> std::process::ExitCode {
    ambit_server_native::init_tracing();
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("notes: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(not(target_os = "hermit"))]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let setting = |name: &str, default: &str| std::env::var(name).unwrap_or(default.to_owned());
    let url = setting("DATABASE_URL", APP_URL);
    let owner_url = setting("DATABASE_OWNER_URL", OWNER_URL);
    let host: std::net::IpAddr = setting("HOST", "127.0.0.1")
        .parse()
        .map_err(|e| format!("HOST: {e}"))?;
    let port: u16 = setting("PORT", "8080")
        .parse()
        .map_err(|e| format!("PORT: {e}"))?;

    let listen = Listen {
        addr: (host, port).into(),
        threads: 8,
        queue: 256,
    };
    let database = Postgres::new(&url, listen.threads).map_err(|e| format!("DATABASE_URL: {e}"))?;
    let app_role = database
        .user()
        .ok_or("DATABASE_URL names no user")?
        .to_owned();

    let owner = Owner::connect(&owner_url)
        .map_err(|e| format!("DATABASE_OWNER_URL (the role that owns the tables): {e}"))?;
    let applied = owner.migrate(notes::SCHEMA)?;
    for version in applied {
        tracing::info!("applied version {version} of schema.sql");
    }
    owner.grant(&app_role)?;
    drop(owner);

    Lockdown::new()
        .allow(&database)
        .allow(&Grant::Listen(listen.addr.port()))
        .apply_or_warn("notes")?;

    tracing::info!("notes listens on http://{}", listen.addr);
    let settings = Settings::from_env(notes::SETTINGS);
    let app = notes::init(StdClock::new(), OsRandom, database, settings)?;
    ambit_server_native::serve(app, listen)?;
    Ok(())
}
