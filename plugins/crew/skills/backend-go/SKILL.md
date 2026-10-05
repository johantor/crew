---
name: backend-go
description: Go backend stack conventions — modules and workspace layout, go build/vet as the gate, error-handling idiom, build tags. Load when the resolved backend stack is go.
---

# Backend: Go

You are working in a Go backend: a module (`go.mod`), the standard library first, and whatever
router/service framework the project already uses (`net/http`, chi, gin, echo — follow the
project, don't introduce a second one).

Match the project's layout rather than importing one. `cmd/<binary>/`, `internal/`, and `pkg/`
are conventions, not requirements; a flat single-package tool is a valid shape. `internal/` is
enforced by the compiler — code outside the module cannot import it, so moving a package in or
out of `internal/` is an API change, not a tidy-up.

## Crew config

`/crew:init` proposes: build `go build ./...` (with `go vet ./...` when the repo runs it), test
`go test ./...` (keeping `-race` if a CI workflow uses it), lint `golangci-lint run` when a
`.golangci.yml`/`.golangci.yaml` exists, else `gofmt -l .`. Format matrix row, extension `go`:
`gofmt -w {file}`, or `gofumpt -w {file}` only when that config enables gofumpt or the
Makefile/CI runs it —
gofumpt rewrites beyond gofmt, so an installed copy alone is not the project's choice.

## Idiom

- Return errors, don't panic. A `panic` in library code is a bug; reserve it for genuinely
  unrecoverable program state in `main`.
- Wrap with `fmt.Errorf("...: %w", err)` so callers can `errors.Is`/`errors.As`. Don't discard
  the cause by formatting it with `%v` when the caller may need to match on it.
- Accept interfaces, return structs. Define the interface where it is *consumed*, not beside the
  implementation.
- A `context.Context` is the first parameter of any **request-scoped or cancellable** call — an
  RPC, a query, an HTTP request — and it is passed through, never stored in a struct. It is not a
  universal I/O rule: `os.ReadFile` and `io.Reader.Read` take no context, and wrapping them to
  accept one buys nothing.
- `go.mod`'s `go` directive sets the language version — don't use a construct newer than it
  without raising the directive deliberately.

## Build

The gate is typically `go build ./...`, usually with `go vet ./...` beside it. Watch/dev forms
that never terminate: `air`, `reflex`, `gow`.

What weakens the gate:

- **A narrowed package pattern.** `go build ./cmd/...` compiles less than `./...` and can
  report clean while another package is broken.
- **Dropping `vet`.** `go build` does not run `go vet`'s checks. When the configured command
  pairs them, run both and report both.
- **A `-tags` the project doesn't configure.** Build tags select which files compile — adding one
  hides a failure rather than fixing it.

**Silence is success.** A clean `go build` prints nothing, so no output is the pass, not a sign
that nothing ran. The cache is content-addressed against the current tree, so a cached result is
a real result — use `-v` or `-x` only when you have a concrete reason to see which packages
compiled. Failures come as `file:line:col: message`; report them deduplicated with a count per
message.

## Lint and format

`gofmt -l .` / `gofumpt -l .` list unformatted files and exit 0, so read the output, not the exit
code. `golangci-lint run` is the usual verify command. Never run the `-w`/`--fix` write forms as
a gate.
