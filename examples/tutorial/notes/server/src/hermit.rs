//! Wiring as a Hermit unikernel: the same app and database as `main.rs`, on ambit's hermit
//! backend.
//!
//! The image is the whole machine: no other files or programs exist in it, so there is nothing
//! to lock down. The settings come from the kernel's command line (`env=NAME=value`, QEMU's
//! `-append`): `DATABASE_URL` and `DATABASE_OWNER_URL` as in `main.rs`, but without defaults,
//! because the unikernel has no Postgres of its own and no user name to take. QEMU's own
//! network reaches the computer it runs on at 10.0.2.2. The server listens on port `PORT`
//! (8080) of every address of the VM.
//!
//! The app's own settings (`SETTINGS` in `lib.rs`) come from the command line too:
//! `env=API_KEY=...`.

use std::process::ExitCode;

// The kernel, with the features Cargo.toml gives it.
use hermit as _;

use ambit_server_hermit::{HermitRandom, Listen, StdClock};
use punk_server::Settings;
use punk_server_postgres::{Owner, Postgres};

pub fn main() -> ExitCode {
    ambit_server_hermit::init_tracing();
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("notes: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let needed = |name: &str| {
        std::env::var(name).map_err(|_| format!("{name} is not set: give it as env={name}=..."))
    };
    let url = needed("DATABASE_URL")?;
    let owner_url = needed("DATABASE_OWNER_URL")?;
    let port: u16 = std::env::var("PORT")
        .unwrap_or("8080".to_owned())
        .parse()
        .map_err(|e| format!("PORT: {e}"))?;

    let listen = Listen {
        addr: ([0, 0, 0, 0], port).into(),
        threads: 4,
        queue: 64,
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

    tracing::info!("notes listens on http://{}", listen.addr);
    let settings = Settings::from_env(notes::SETTINGS);
    let app = notes::init(StdClock::new(), HermitRandom::new()?, database, settings)?;
    ambit_server_hermit::serve(app, listen)?;
    Ok(())
}
