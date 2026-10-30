#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

standard
criterion "a list page type" has 'class [A-Za-z]*List[A-Za-z]* : PageData' src/EvalSite/Models/Pages
criterion "the session tested GetPage" has 'GetPage\(' tests
criterion "a view links the next page" has 'page=' src/EvalSite/Views
criterion "hidden GetPage tests" hidden_tests_pass
verdict
