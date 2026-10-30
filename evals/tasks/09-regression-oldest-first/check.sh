#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

standard
criterion "hidden ordering tests" hidden_tests_pass
verdict
