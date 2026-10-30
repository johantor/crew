#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

view=src/EvalSite/Views/ArticlePage/Index.cshtml
standard
criterion "no Html.Raw in the views" lacks 'Html\.Raw' src/EvalSite/Views
criterion "MainBody renders through epi-property or PropertyFor" has 'epi-property="@Model\.MainBody"|PropertyFor\(m => m\.MainBody\)' "$view"
verdict
