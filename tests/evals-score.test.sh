#!/usr/bin/env bash
# Behavior tests for evals/score.sh: one summary scores passes, errors and medians; two put the
# base and the variant side by side, mark only the tasks whose passes changed, and warn when
# the runs are uneven; bad input is refused.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SCORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../evals" && pwd)/score.sh"

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then _pass; else _fail "$1: expected [$2], got [$3]"; fi
}

# line <label> — the score's line for a task or summary row, spaces squeezed.
line() { grep -E "^$1 " <<<"$_out" | tr -s ' '; }

# score <files...> — sets _status, _out (stdout) and _err (stderr).
score() {
  _status=0
  _out="$(bash "$SCORE" "$@" 2>"$FIXTURE_ROOT/score-err")" || _status=$?
  _err="$(cat "$FIXTURE_ROOT/score-err")"
}

dir="$(new_tmpdir)"
cat >"$dir/base.jsonl" <<'EOF'
{"task":"01-rename-teaser","run":1,"verdict":"pass","duration_ms":360000,"num_turns":30,"total_cost_usd":1.2,"is_error":false}
{"task":"01-rename-teaser","run":2,"verdict":"pass","duration_ms":480000,"num_turns":34,"total_cost_usd":1.6,"is_error":false}
{"task":"09-regression-oldest-first","run":1,"verdict":"pass","duration_ms":600000,"num_turns":50,"total_cost_usd":2.0,"is_error":false}
{"task":"09-regression-oldest-first","run":2,"verdict":"fail","is_error":true,"note":"no JSON result"}
EOF
cat >"$dir/variant.jsonl" <<'EOF'
{"task":"01-rename-teaser","run":1,"verdict":"pass","duration_ms":300000,"num_turns":20,"total_cost_usd":1.0,"is_error":false}
{"task":"01-rename-teaser","run":2,"verdict":"pass","duration_ms":300000,"num_turns":20,"total_cost_usd":1.0,"is_error":false}
{"task":"09-regression-oldest-first","run":1,"verdict":"fail","duration_ms":600000,"num_turns":50,"total_cost_usd":2.0,"is_error":false}
{"task":"09-regression-oldest-first","run":2,"verdict":"fail","duration_ms":600000,"num_turns":50,"total_cost_usd":2.0,"is_error":false}
EOF

score "$dir/base.jsonl"
check "one summary exits 0" "0" "$_status"
check "a task line counts its passes" "01-rename-teaser 2/2" "$(line 01-rename-teaser)"
check "the total counts every run" "total 3/4" "$(line total)"
check "a session with no result counts as an error" "session errors 1" "$(line 'session errors')"
check "the median cost skips a run with no cost" "median cost \$ 1.6" "$(line 'median cost \$')"
check "the median is the middle run" "median turns 34" "$(line 'median turns')"
check "minutes come from duration_ms" "median minutes 8" "$(line 'median minutes')"

score "$dir/base.jsonl" "$dir/variant.jsonl"
check "a pair exits 0" "0" "$_status"
check "a changed task is marked" "09-regression-oldest-first 1/2 0/2 <- flipped" "$(line 09-regression-oldest-first)"
check "an unchanged task is not marked" "01-rename-teaser 2/2 2/2" "$(line 01-rename-teaser)"
check "the totals sit side by side" "total 3/4 2/4" "$(line total)"
check "an even count takes the mean of the middle pair" "median cost \$ 1.6 1.5" "$(line 'median cost \$')"
check "even runs raise no warning" "" "$_err"

head -n 3 "$dir/variant.jsonl" >"$dir/short.jsonl"
score "$dir/base.jsonl" "$dir/short.jsonl"
check "uneven runs still score" "0" "$_status"
check "uneven runs are named" "1" "$(grep -c 'the comparison is uneven' <<<"$_err")"

head -n 2 "$dir/variant.jsonl" >"$dir/one-task.jsonl"
score "$dir/base.jsonl" "$dir/one-task.jsonl"
check "a task one side never ran shows a dash" "09-regression-oldest-first 1/2 - <- flipped" "$(line 09-regression-oldest-first)"

printf 'not json\n' >"$dir/bad.jsonl"
score "$dir/bad.jsonl"
check "a file that is not a summary is refused" "2" "$_status"
: >"$dir/empty.jsonl"
score "$dir/empty.jsonl"
check "an empty summary is refused" "2" "$_status"
score
check "no argument is refused" "2" "$_status"

finish
