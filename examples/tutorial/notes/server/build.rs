//! Compiles the punk app (`../Notes.punk`) into `libapp.a` with `punk build`, and links it
//! into this crate. The compiler is `punk` on your PATH, or the one in the `PUNK` environment
//! variable.

use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let app_dir = manifest.join("..");
    let app = app_dir.join("Notes.punk");
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let punk = std::env::var_os("PUNK")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("punk"));

    println!("cargo:rerun-if-env-changed=PUNK");
    // The app and its own modules.
    for entry in std::fs::read_dir(&app_dir).unwrap().flatten() {
        let path = entry.path();
        if matches!(
            path.extension().and_then(|e| e.to_str()),
            Some("punk" | "sql")
        ) {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }

    let target = match std::env::var("TARGET").unwrap().as_str() {
        "x86_64-unknown-linux-gnu" => "x64glibc",
        "aarch64-unknown-linux-gnu" => "arm64glibc",
        "x86_64-unknown-linux-musl" => "x64musl",
        "aarch64-unknown-linux-musl" => "arm64musl",
        "x86_64-apple-darwin" => "x64mac",
        "aarch64-apple-darwin" => "arm64mac",
        other => panic!("punk's server platform has no target for {other} yet"),
    };
    let archive = out.join("libapp.a");
    let status = Command::new(&punk)
        .arg("build")
        .arg(format!("--target={target}"))
        .arg(format!("--output={}", archive.display()))
        .arg(&app)
        .status()
        .unwrap_or_else(|e| {
            panic!(
                "could not run {} ({e}); install punk-lang, or set PUNK to the compiler",
                punk.display()
            )
        });
    assert!(status.success(), "punk build failed for {}", app.display());

    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=app");
}
