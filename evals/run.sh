#!/usr/bin/env bash
# Runs eval tasks end to end: each run copies the fixture into a fresh git repo, runs the
# task's setup.sh, hands prompt.md to a headless `claude --agent crew:lead`, then grades the
# tree with the task's check.sh. Method and decision rules: evals/README.md.
#
# usage: evals/run.sh [-n runs] <task>...   (a task is a directory name under evals/tasks/, or `all`)
# env:   CREW_EVAL_PLUGIN  plugin dir under test (default: this checkout's plugin/)
#        CREW_EVAL_OUT     results root (default: $TMPDIR/crew-evals; outside any checkout, since a
#                          session reads every CLAUDE.md above its work tree)
set -uo pipefail

EVAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EVAL_ROOT
plugin="${CREW_EVAL_PLUGIN:-$EVAL_ROOT/../plugin}"
plugin="$(cd "$plugin" && pwd)" || { echo "run.sh: no plugin dir at $plugin" >&2; exit 2; }
out_root="${CREW_EVAL_OUT:-${TMPDIR:-/tmp}/crew-evals}"

runs=2
if [ "${1:-}" = "-n" ]; then
  runs="${2:-}"
  shift 2
fi
case "$runs" in '' | *[!0-9]* | 0) echo "run.sh: -n takes a positive count" >&2; exit 2 ;; esac
[ "$#" -gt 0 ] || { echo "usage: evals/run.sh [-n runs] <task>... | all" >&2; exit 2; }
for tool in claude dotnet git jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "run.sh: $tool is required" >&2; exit 2; }
done

tasks=()
if [ "$1" = all ]; then
  for dir in "$EVAL_ROOT"/tasks/*/; do tasks+=("$(basename "$dir")"); done
else
  tasks=("$@")
fi
for task in "${tasks[@]}"; do
  if [ ! -f "$EVAL_ROOT/tasks/$task/prompt.md" ] || [ ! -f "$EVAL_ROOT/tasks/$task/check.sh" ]; then
    echo "run.sh: $task has no prompt.md and check.sh under evals/tasks/" >&2
    exit 2
  fi
done

out="$out_root/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out" || exit 2
# Only what a crew run needs; the gate script is named by path since it takes a command string.
allowed=(Agent Skill Read Glob Grep Edit Write TodoWrite "Bash(git:*)" "Bash(dotnet:*)" "Bash(bash $plugin/scripts/gate.sh:*)")

for task in "${tasks[@]}"; do
  task_dir="$EVAL_ROOT/tasks/$task"
  for n in $(seq 1 "$runs"); do
    run_dir="$out/$task-$n"
    work="$run_dir/work"
    mkdir -p "$work" && cp -R "$EVAL_ROOT/fixture/." "$work/" || exit 2
    (
      cd "$work" &&
        git init -q -b main &&
        git add -A &&
        git -c user.name=eval -c user.email=eval@example.invalid commit -qm "Initial site" &&
        if [ -f "$task_dir/setup.sh" ]; then bash "$task_dir/setup.sh"; fi
    ) >"$run_dir/setup.log" 2>&1 || { echo "run.sh: $task-$n setup failed, see $run_dir/setup.log" >&2; exit 2; }
    base="$(git -C "$work" rev-parse main)"

    # "Just build it" is the standing go-ahead that skips the plan checkpoint, as a user would give it.
    (cd "$work" && claude -p "$(cat "$task_dir/prompt.md")"$'\n\nJust build it.' \
      --agent crew:lead --plugin-dir "$plugin" --output-format json \
      --permission-mode acceptEdits --allowedTools "${allowed[@]}" </dev/null) >"$run_dir/session.json" 2>"$run_dir/session.err"

    (cd "$work" && EVAL_BASE="$base" EVAL_TASK_DIR="$task_dir" bash "$task_dir/check.sh") >"$run_dir/grade.log" 2>&1
    grade=$?
    verdict=pass
    [ "$grade" -eq 0 ] || verdict=fail

    session="$(jq -c '{duration_ms, num_turns, total_cost_usd, usage, is_error}' "$run_dir/session.json" 2>/dev/null)" ||
      session='{"is_error":true,"note":"no JSON result"}'
    jq -nc --arg task "$task" --argjson run "$n" --arg verdict "$verdict" --arg plugin "$plugin" \
      --argjson session "$session" '{task: $task, run: $run, verdict: $verdict, plugin: $plugin} + $session' \
      >>"$out/summary.jsonl"
    echo "$task #$n: $verdict"
  done
done
echo "results: $out/summary.jsonl"
