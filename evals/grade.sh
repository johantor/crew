#!/usr/bin/env bash
# Sourced by each task's check.sh, which run.sh runs from the session's work tree with
# EVAL_BASE (the base commit the session started from) and EVAL_TASK_DIR set. Each
# criterion prints one PASS or FAIL line; `verdict` exits 0 only when every one passed.
set -uo pipefail

failed=0

# criterion <label> <command...> — the command's output is dropped; only its exit counts.
criterion() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    failed=1
  fi
}

# Source only: the build output under bin/ and obj/ quotes the CMS's own type names.
has() { grep -rqE --exclude-dir=bin --exclude-dir=obj "$1" "${@:2}"; }
lacks() { ! has "$@"; }

on_feature_branch() { [ "$(git rev-parse --abbrev-ref HEAD)" != main ] && [ -n "$(git log --oneline main..HEAD)" ]; }
main_untouched() { [ "$(git rev-parse main)" = "$EVAL_BASE" ]; }
# The plan file lands in the untracked .claude/ fallback; it is the run's state, not its work.
tree_clean() { [ -z "$(git status --porcelain -- . ':!.claude')" ]; }

# The checks every task shares: git posture first (before hidden tests touch the tree), then the gate.
standard() {
  criterion "work committed on a feature branch" on_feature_branch
  criterion "base branch untouched" main_untouched
  criterion "working tree clean" tree_clean
  criterion "build" dotnet build
  criterion "tests" dotnet test
  criterion "lint" dotnet format --verify-no-changes
}

# Runs the task's hidden/*.cs tests, which the session never saw, against its result.
hidden_tests_pass() {
  mkdir -p tests/EvalSite.Tests/Hidden &&
    cp "$EVAL_TASK_DIR"/hidden/*.cs tests/EvalSite.Tests/Hidden/ &&
    dotnet test --filter "FullyQualifiedName~EvalSite.Tests.Hidden"
}

verdict() { exit "$failed"; }
