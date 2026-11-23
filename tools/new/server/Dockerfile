# @app@ as a container: one static program (Rust and the compiled punk app,
# linked against musl) on an image with nothing else in it but certificates.
#
#     docker build -t @app@ .
#     docker run --rm -p 8080:8080 \
#         -e DATABASE_URL='postgres://@crate@_app:...@db.example.com/@app@' \
#         -e DATABASE_OWNER_URL='postgres://owner:...@db.example.com/@app@' \
#         @app@
#
# The database runs elsewhere: on another machine, a managed service, or a
# container of its own. A database that isn't on this machine gets TLS (see
# README.md). The image builds on Linux and on a Mac, for the computer's own
# kind of processor (`docker build --platform linux/amd64` for another).

# The build: Rust, punk-lang (from its release, checked against SHA256SUMS),
# and a C compiler for musl (the TLS library has a little C).
FROM rust:@rust@-slim-trixie AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl musl-tools \
    && rm -rf /var/lib/apt/lists/*
# The image's Rust is the one the platforms use; without its extras (rustfmt, clippy).
ENV RUSTUP_TOOLCHAIN=@rust@
ARG PUNK_VERSION=@version@
# A punk archive in this folder instead of a release (to try an unreleased punk).
ARG PUNK_ARCHIVE=
WORKDIR /app
COPY . .
RUN if [ -n "$PUNK_ARCHIVE" ]; then export PUNK_ARCHIVE="/app/$PUNK_ARCHIVE"; fi \
    && curl --proto '=https' -fsSL "https://raw.githubusercontent.com/eelcoh/punk/$PUNK_VERSION/install.sh" \
        | PUNK_VERSION="$PUNK_VERSION" PUNK_HOME=/opt/punk PUNK_BIN_DIR=/usr/local/bin sh
RUN target="$(uname -m)-unknown-linux-musl" \
    && cd server \
    && rustup target add "$target" \
    && cargo build --release --locked --target "$target" \
    && cp "target/$target/release/@app@" /@app@

# The image: the program, as a user without rights, and nothing to run but it.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /@app@ /@app@
ENV HOST=0.0.0.0 PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/@app@"]
