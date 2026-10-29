#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091,SC2329  # the helpers below run through `criterion`
source "$EVAL_ROOT/grade.sh"

new_test_file() { [ -n "$(git diff --name-only --diff-filter=A "$EVAL_BASE" -- tests)" ]; }

standard
criterion "the ancestors come from IContentLoader" has 'GetAncestors\(' src
criterion "a view renders a breadcrumb nav" has '<nav[^>]*aria-label="[Bb]readcrumb' src/EvalSite/Views
criterion "the session added a test file" new_test_file
verdict
