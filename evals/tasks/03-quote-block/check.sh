#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091,SC2329  # the helpers below run through `criterion`
source "$EVAL_ROOT/grade.sh"

quote_type_has_guid() {
  grep -rlE --exclude-dir=bin --exclude-dir=obj 'class Quote[A-Za-z]* : BlockData' src | xargs grep -qE 'GUID = "[0-9a-fA-F-]{36}"'
}

standard
criterion "a quote block type" has 'class Quote[A-Za-z]* : BlockData' src
criterion "its content type has a GUID" quote_type_has_guid
criterion "the start page allows it" has 'AllowedTypes\(.*Quote' src/EvalSite/Models/Pages/StartPage.cs
criterion "a view renders a blockquote" has '<blockquote' src/EvalSite/Views
criterion "a view renders a cite" has '<cite' src/EvalSite/Views
verdict
