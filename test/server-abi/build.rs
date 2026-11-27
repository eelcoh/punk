//! Link the fixture against the same compiler and host that build server apps.

use std::{env, path::PathBuf, process::Command};

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let repo = manifest.join("../..");
    let punk = repo.join("zig-out/bin/punk");
    let app = manifest.join("Roundtrip.punk");
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let archive = out.join("libapp.a");

    for path in [&app, &punk, &repo.join("zig-out/libexec/punk")] {
        println!("cargo:rerun-if-changed={}", path.display());
    }
    for entry in std::fs::read_dir(repo.join("platforms/server")).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_some_and(|ext| ext == "roc") {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }

    let target = match env::var("TARGET").unwrap().as_str() {
        "x86_64-unknown-linux-gnu" => "x64glibc",
        "aarch64-unknown-linux-gnu" => "arm64glibc",
        "x86_64-unknown-linux-musl" => "x64musl",
        "aarch64-unknown-linux-musl" => "arm64musl",
        "x86_64-apple-darwin" => "x64mac",
        "aarch64-apple-darwin" => "arm64mac",
        other => panic!("punk's server platform has no target for {other} yet"),
    };
    let status = Command::new(&punk)
        .arg("build")
        .arg(format!("--target={target}"))
        .arg(format!("--output={}", archive.display()))
        .arg(&app)
        .status()
        .unwrap_or_else(|err| {
            panic!(
                "could not run {}: {err}. Run zig build first",
                punk.display()
            )
        });
    assert!(status.success(), "punk build failed for {}", app.display());

    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=app");
}
