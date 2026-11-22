//! TLS to Postgres, with rustls: the connection string says whether, and the certificate of the
//! server is always checked.
//!
//! - `sslmode=disable` is a connection without TLS: for a database on the same machine or a
//!   private network.
//! - `sslmode=prefer` is TLS when the server has it, else without.
//! - `sslmode=require`, `verify-ca` and `verify-full` are TLS or no connection.
//! - Without `sslmode`, a database on this machine (`localhost`, a loopback address or a Unix
//!   socket) is `disable`, since nothing crosses a network (and such a database often has a
//!   certificate of its own making, as Debian's does), and any other is `require`: a connection
//!   over a network is not quietly without TLS.
//!
//! In each mode with TLS the server's certificate must be valid for its host name and signed by
//! a certificate authority punk trusts, also with `require` (where libpq checks nothing). Those
//! are the authorities of Mozilla's list (`webpki-roots`, built in, so an image without
//! `/etc/ssl` works), or the ones in the PEM file `sslrootcert=<file>` names (a cloud's own
//! authority, or yours), and then only those.

use std::sync::Arc;

use postgres::config::{Host, SslMode};
use punk_server::DbError;
use rustls::RootCertStore;
use rustls::pki_types::CertificateDer;
use rustls::pki_types::pem::PemObject;
use tokio_postgres_rustls::MakeRustlsConnect;

/// A connection string read for a pool or an owner: the settings `postgres` knows, and what
/// TLS needs.
pub(crate) struct Settings {
    pub config: postgres::Config,
    pub tls: MakeRustlsConnect,
}

/// Reads `url` (`postgres://...` or `host=... user=...`), with the TLS settings above.
pub(crate) fn settings(url: &str) -> Result<Settings, DbError> {
    let (url, mode, root_cert) = take_tls_options(url)?;
    let mut config: postgres::Config = url.parse().map_err(|e: postgres::Error| {
        DbError::new("08000", format!("bad connection string: {e}"))
    })?;
    match mode.as_deref() {
        None if is_local(&config) => config.ssl_mode(SslMode::Disable),
        None | Some("require" | "verify-ca" | "verify-full") => config.ssl_mode(SslMode::Require),
        Some("prefer") => config.ssl_mode(SslMode::Prefer),
        Some("disable") => config.ssl_mode(SslMode::Disable),
        Some(other) => {
            return Err(DbError::new(
                "08000",
                format!(
                    "bad connection string: sslmode={other} (give disable, prefer, require, verify-ca or verify-full)"
                ),
            ));
        }
    };
    let tls = connector(root_cert.as_deref())?;
    Ok(Settings { config, tls })
}

/// A connector that checks certificates against `root_cert` (a PEM file), or Mozilla's list.
pub(crate) fn connector(root_cert: Option<&str>) -> Result<MakeRustlsConnect, DbError> {
    let mut roots = RootCertStore::empty();
    match root_cert {
        None | Some("system") => roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned()),
        Some(file) => {
            let bad = |e: &dyn std::fmt::Display| {
                DbError::new("08000", format!("sslrootcert={file}: {e}"))
            };
            let certs = CertificateDer::pem_file_iter(file)
                .map_err(|e| bad(&e))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| bad(&e))?;
            if certs.is_empty() {
                return Err(bad(&"no certificate in the file"));
            }
            for cert in certs {
                roots.add(cert).map_err(|e| bad(&e))?;
            }
        }
    }
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|e| DbError::new("08000", format!("TLS: {e}")))?
        .with_root_certificates(roots)
        .with_no_client_auth();
    Ok(MakeRustlsConnect::new(config))
}

/// Whether each host of the connection string is this machine.
fn is_local(config: &postgres::Config) -> bool {
    config.get_hosts().iter().all(|host| match host {
        #[cfg(unix)]
        Host::Unix(_) => true,
        Host::Tcp(name) => {
            name == "localhost"
                || name
                    .trim_start_matches('[')
                    .trim_end_matches(']')
                    .parse::<std::net::IpAddr>()
                    .is_ok_and(|ip| ip.is_loopback())
        }
    })
}

/// `url` without `sslmode` and `sslrootcert` (the `postgres` crate doesn't know `verify-ca`,
/// `verify-full` or `sslrootcert`), and their values.
fn take_tls_options(url: &str) -> Result<(String, Option<String>, Option<String>), DbError> {
    let mut mode = None;
    let mut root_cert = None;
    let mut take = |key: &str, value: String| match key {
        "sslmode" => {
            mode = Some(value);
            true
        }
        "sslrootcert" => {
            root_cert = Some(value);
            true
        }
        _ => false,
    };
    let rest = if url.contains("://") {
        // postgres://user@host/db?sslmode=require&sslrootcert=/ca.pem
        match url.split_once('?') {
            None => url.to_owned(),
            Some((base, query)) => {
                let kept: Vec<&str> = query
                    .split('&')
                    .filter(|pair| {
                        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
                        !take(key, percent_decode(value))
                    })
                    .collect();
                if kept.is_empty() {
                    base.to_owned()
                } else {
                    format!("{base}?{}", kept.join("&"))
                }
            }
        }
    } else {
        // host=db.example.com user=app sslmode=verify-full sslrootcert=/ca.pem
        let mut kept = Vec::new();
        for word in url.split_whitespace() {
            match word.split_once('=') {
                Some((key, value)) if !value.starts_with('\'') && take(key, value.to_owned()) => {}
                _ => kept.push(word),
            }
        }
        kept.join(" ")
    };
    Ok((rest, mode, root_cert))
}

/// `%2F` and the like as the bytes they stand for (a file name in a URL).
fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = |b: u8| (b as char).to_digit(16);
        if bytes[i] == b'%'
            && let (Some(Some(hi)), Some(Some(lo))) = (
                bytes.get(i + 1).map(|&b| hex(b)),
                bytes.get(i + 2).map(|&b| hex(b)),
            )
        {
            out.push((hi * 16 + lo) as u8);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mode(url: &str) -> SslMode {
        settings(url).unwrap().config.get_ssl_mode()
    }

    #[test]
    fn a_database_elsewhere_needs_tls() {
        assert_eq!(
            mode("postgres://app@db.example.com/notes"),
            SslMode::Require
        );
        assert_eq!(mode("host=10.0.0.5 user=app"), SslMode::Require);
    }

    #[test]
    fn a_database_here_goes_without() {
        assert_eq!(mode("postgres://app@localhost/notes"), SslMode::Disable);
        assert_eq!(mode("postgres://app@127.0.0.1/notes"), SslMode::Disable);
        assert_eq!(mode("host=/var/run/postgresql user=app"), SslMode::Disable);
    }

    #[test]
    fn the_connection_string_decides() {
        assert_eq!(
            mode("postgres://app@db/notes?sslmode=disable"),
            SslMode::Disable
        );
        assert_eq!(
            mode("postgres://app@localhost/notes?sslmode=require"),
            SslMode::Require
        );
        assert_eq!(
            mode("postgres://app@db/notes?sslmode=verify-full&connect_timeout=3"),
            SslMode::Require
        );
        assert_eq!(mode("host=db user=app sslmode=verify-ca"), SslMode::Require);
        assert!(settings("postgres://app@db/notes?sslmode=sometimes").is_err());
    }

    #[test]
    fn the_other_options_stay() {
        let (url, mode, root) = take_tls_options(
            "postgres://app@db/notes?sslmode=verify-full&sslrootcert=%2Fca.pem&application_name=x",
        )
        .unwrap();
        assert_eq!(url, "postgres://app@db/notes?application_name=x");
        assert_eq!(mode.as_deref(), Some("verify-full"));
        assert_eq!(root.as_deref(), Some("/ca.pem"));
        let config: postgres::Config = url.parse().unwrap();
        assert_eq!(config.get_application_name(), Some("x"));
    }

    #[test]
    fn a_missing_root_certificate_is_an_error() {
        let Err(e) = settings("postgres://app@db/notes?sslrootcert=/nothing/here.pem") else {
            panic!("expected an error");
        };
        assert!(
            e.message.contains("sslrootcert=/nothing/here.pem"),
            "{}",
            e.message
        );
    }
}
