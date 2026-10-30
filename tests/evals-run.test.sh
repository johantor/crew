#!/usr/bin/env bash
# Behavior tests for evals/run.sh, with `claude` and `dotnet` stubbed: a session that fixes
# the task on a feature branch grades pass, one that does nothing grades fail, the session
# gets crew:lead and the standing go-ahead, and bad arguments are refused before any run.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../evals" && pwd)/run.sh"

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then _pass; else _fail "$1: expected [$2], got [$3]"; fi
}

stubs="$(new_tmpdir)"
# dotnet always succeeds, so the grade turns on git posture and the task's own criteria.
printf '#!/bin/sh\nexit 0\n' >"$stubs/dotnet"
# claude records its arguments and, when CLAUDE_STUB_FIX is set, fixes task 07 on a branch.
cat >"$stubs/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$CLAUDE_STUB_ARGS"
if [ -n "${CLAUDE_STUB_FIX:-}" ]; then
  git checkout -qb feature/inject-url-resolver
  printf 'public class TeaserBlockComponent(IUrlResolver urlResolver) : BlockComponent<TeaserBlock> { }\n' \
    >src/EvalSite/Components/TeaserBlockComponent.cs
  git -c user.name=stub -c user.email=stub@example.invalid commit -qam "Inject IUrlResolver"
fi
[ -n "${CLAUDE_STUB_SILENT:-}" ] && exit 1
echo '{"type":"result","is_error":false,"duration_ms":1200,"num_turns":3,"total_cost_usd":0.5,"usage":{"input_tokens":10,"output_tokens":5}}'
EOF
chmod +x "$stubs/dotnet" "$stubs/claude"
export PATH="$stubs:$PATH" CLAUDE_STUB_ARGS="$FIXTURE_ROOT/claude-args"

# run_eval <out-dir> [run.sh args...] — sets _status and _summary (the run's summary.jsonl).
run_eval() {
  local out="$1"
  shift
  _status=0
  CREW_EVAL_OUT="$out" bash "$RUN" "$@" >/dev/null 2>"$FIXTURE_ROOT/run-err" || _status=$?
  _summary="$(cat "$out"/*/summary.jsonl 2>/dev/null)"
}

out="$(new_tmpdir)"
CLAUDE_STUB_FIX=1 run_eval "$out" -n 1 07-debt-service-locator
check "a fixing session exits 0" "0" "$_status"
check "a fixing session grades pass" "pass" "$(jq -r .verdict <<<"$_summary")"
check "the summary carries the session's cost" "0.5" "$(jq -r .total_cost_usd <<<"$_summary")"
check "the session runs as crew:lead" "crew:lead" "$(grep -A1 -- '^--agent$' "$CLAUDE_STUB_ARGS" | tail -n 1)"
check "the prompt carries the standing go-ahead" "1" "$(grep -c '^Just build it\.$' "$CLAUDE_STUB_ARGS")"
check "the gate rule reaches claude as one argument" "1" "$(grep -c '^Bash(bash .*/scripts/gate\.sh:\*)$' "$CLAUDE_STUB_ARGS")"
check "the session never skips permissions" "0" "$(grep -c -- '--dangerously-skip-permissions' "$CLAUDE_STUB_ARGS")"

out="$(new_tmpdir)"
run_eval "$out" -n 2 07-debt-service-locator
check "an idle session grades fail, once per run" "fail fail" "$(jq -r .verdict <<<"$_summary" | xargs)"
check "the grade names the missing branch" "1" \
  "$(grep -c '^FAIL work committed on a feature branch' "$out"/*/07-debt-service-locator-1/grade.log)"

out="$(new_tmpdir)"
CLAUDE_STUB_SILENT=1 run_eval "$out" -n 1 07-debt-service-locator
check "a session with no output still gets a summary line" "fail true" \
  "$(jq -r '"\(.verdict) \(.is_error)"' <<<"$_summary")"

out="$(new_tmpdir)"
run_eval "$out" -n 1 07-debt-service-locator &
run_eval "$out" -n 1 07-debt-service-locator
wait
check "two runs in the same second get their own directories" "2" "$(find "$out" -name summary.jsonl | wc -l | tr -d ' ')"

out="$(new_tmpdir)"
run_eval "$out" no-such-task
check "an unknown task is refused" "2" "$_status"
check "an unknown task runs nothing" "" "$_summary"
run_eval "$out" -n 0 07-debt-service-locator
check "-n 0 is refused" "2" "$_status"

finish
