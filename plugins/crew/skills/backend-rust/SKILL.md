---
name: backend-rust
description: Rust backend stack conventions — cargo workspaces, check/build/clippy as the gate, features and editions, and the inline `#[cfg(test)]` ownership split with oracle. Load when the resolved backend stack is rust.
---

# Backend: Rust

You are working in a Rust backend: a cargo package or workspace (`Cargo.toml`), and whatever
async runtime and framework the project already uses (tokio + axum, actix-web, or a plain binary
crate — follow the project).

Read `Cargo.toml` before you add anything. The `edition`, the workspace members, and the
`[features]` table all change what compiles; a workspace's `[workspace.dependencies]` is where a
shared version lives, and adding the same crate at a member's own version is a divergence, not a
convenience.

## Crew config

`/crew:init` proposes: build `cargo check --all-targets` or `cargo build` — read which the repo's
CI runs rather than picking — with `cargo clippy --all-targets -- -D warnings` where clippy is
configured; test `cargo test` (`cargo nextest run` when nextest is configured); lint
`cargo fmt --check`. Format matrix: one row per crate, extension `rs`, `rustfmt --skip-children
--edition <edition> {file}` with the edition from the crate's own `Cargo.toml` (or the
workspace's when it inherits with `edition.workspace = true`; omitted means 2015, not
inheritance). Bare `rustfmt` reads no manifest, and `cargo fmt` formats the whole package, so
it stays at the gate.

## Idiom

- Return `Result<T, E>` and propagate with `?`. Reserve `unwrap`/`expect` for cases you can argue
  are unreachable, and say why in the `expect` message.
- Errors: `thiserror` for a library's typed errors, `anyhow` for a binary's context chain. Follow
  whichever the project already has rather than adding the other.
- Prefer borrowing to cloning, but don't contort a lifetime to avoid one `clone` in cold code.
- A public API change (visibility, signature, trait bound) is a semver event in a library crate —
  say so in your findings rather than treating it as an internal edit.

## Inline unit tests are a shared-file split

Rust puts unit tests **inside the source file** in a `#[cfg(test)] mod tests` block, while
integration tests live in `tests/`. That makes a `.rs` file shared by concern, the same way a
Razor view is:

- **`tests/**` is `oracle`'s** — integration tests, by file.
- **An inline `#[cfg(test)]` block is yours**, because it lives in a file in your lane and
  `oracle` cannot write it without touching your production code.

So write the inline unit tests for code you implement, and coordinate with `morpheus` on what
`oracle` covers from `tests/` rather than leaving a module untested because the tests would have
to live in your file.

## Build

The gate is typically `cargo check` or `cargo build`, usually with `cargo clippy` beside it.
`cargo watch` never terminates.

What weakens the gate:

- **A relaxed lint level.** `--cap-lints`, an `#[allow(...)]` added to silence a finding you were
  asked to fix, or a `-D warnings` dropped from a configured `RUSTFLAGS`. Lint configuration
  belongs to `Cargo.toml`/`clippy.toml`.
- **A narrowed target set.** `--lib` or `-p <one-member>` compiles less than the workspace;
  `--all-targets` includes tests and benches, which is usually what the gate wants.
- **`check` in place of a configured `build`.** `cargo check` skips codegen, so it will not catch
  a monomorphization or link error. If the project gates on `check`, that is its choice.
- **A feature flag the project doesn't configure**, `--no-default-features` included, to route
  around a broken module.

`cargo build` exits 0 with warnings present unless the project sets `-D warnings`. Report every
warning as the lint name, `file:line`, and a count per lint.

## `target/` is per-writer state

Cargo takes a lock on `target/`, so a second concurrent build **blocks** rather than corrupting —
you will see "Blocking waiting for file lock on build directory". That is contention, not a code
error, and not the user's dev server. If another crew build may be live against the same package,
either wait for it or set `CARGO_TARGET_DIR` to your own path before you start, and say which you
did in your findings.
