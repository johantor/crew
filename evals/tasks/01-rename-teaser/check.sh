#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

standard
criterion "ArticlePage has Summary" has 'virtual string\? Summary' src/EvalSite/Models/Pages/ArticlePage.cs
criterion "ArticlePage has no Teaser" lacks 'Teaser' src/EvalSite/Models/Pages/ArticlePage.cs
criterion "a migration keeps the stored values" has 'UsedToBeNamed\("Teaser"\)' src
criterion "no view still reads Teaser" lacks '\.Teaser([^A-Za-z0-9_]|$)' src/EvalSite/Views
verdict
