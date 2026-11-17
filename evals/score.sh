#!/usr/bin/env bash
# Scores eval runs from run.sh's summary.jsonl: passes per task, session errors, and the median
# cost, turns and minutes. Given a second summary (the variant), it puts both side by side and
# marks each task whose pass count changed, the ones evals/README.md says to read.
#
# usage: evals/score.sh <summary.jsonl> [<variant summary.jsonl>]
set -uo pipefail

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "usage: evals/score.sh <summary.jsonl> [<variant summary.jsonl>]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "score.sh: jq is required" >&2; exit 2; }
for f in "$@"; do
  jq -e -s 'length > 0 and all(.[]; type == "object" and has("task") and has("verdict"))' "$f" >/dev/null 2>&1 ||
    { echo "score.sh: $f is not a run.sh summary.jsonl" >&2; exit 2; }
done

jq -rn --slurpfile a "$1" --slurpfile b "${2:-$1}" --argjson pair "$(($# == 2))" '
  def med: sort | length as $n | if $n == 0 then null
    elif $n % 2 == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
  def num(d): if . == null then "-" else (. * pow(10; d) | round) / pow(10; d) | tostring end;
  def pad(n): tostring | if length < n then . + (" " * (n - length)) else . + " " end;
  def passes: "\(map(select(.verdict == "pass")) | length)/\(length)";
  def per_task: group_by(.task) | map({key: .[0].task, value: .}) | from_entries;

  ($a | per_task) as $ta | ($b | per_task) as $tb
  | ([$ta, $tb | keys[]] | unique) as $tasks
  | ($tasks + ["median minutes"] | map(length) | max + 2) as $w
  | def row(name; f): (name | pad($w))
      + (if $pair == 1 then ($a | f | pad(10)) + ($b | f | tostring) else $a | f | tostring end);
    def task_row(t): ($ta[t] | if . then passes else "-" end) as $x
      | ($tb[t] | if . then passes else "-" end) as $y
      | (t | pad($w)) + (if $pair == 1 then ($x | pad(10)) + ($y | pad(10))
          + (if $x != $y then "<- flipped" else "" end) | sub(" +$"; "") else $x end);
  (if $pair == 1 then ("task" | pad($w)) + ("base" | pad(10)) + "variant" else ("task" | pad($w)) + "passes" end),
  ($tasks[] | task_row(.)),
  row("total"; passes),
  row("session errors"; map(select(.is_error == true)) | length),
  row("median cost $"; map(.total_cost_usd // empty) | med | num(2)),
  row("median turns"; map(.num_turns // empty) | med | num(1)),
  row("median minutes"; map(.duration_ms // empty) | med | if . == null then null else . / 60000 end | num(1))
' || exit 2

# The README rule: compare one change at a time, on the same tasks and run count.
if [ "$#" -eq 2 ]; then
  shape='group_by(.task) | map({(.[0].task): length}) | add'
  [ "$(jq -sc "$shape" "$1")" = "$(jq -sc "$shape" "$2")" ] ||
    echo "score.sh: the two summaries differ in tasks or run counts; the comparison is uneven" >&2
fi
exit 0
