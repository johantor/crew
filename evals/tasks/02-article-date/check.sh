#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

view=src/EvalSite/Views/ArticlePage/Index.cshtml
standard
criterion "the article view has a <time> element" has '<time' "$view"
criterion "it renders ArticleDate" has 'ArticleDate' "$view"
criterion "datetime is yyyy-MM-dd" has 'yyyy-MM-dd' "$view"
verdict
