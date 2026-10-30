#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091
source "$EVAL_ROOT/grade.sh"

standard
criterion "no ServiceLocator in the site" lacks 'ServiceLocator' src
criterion "the component takes IUrlResolver by constructor" has 'TeaserBlockComponent\(.*IUrlResolver' src/EvalSite/Components
verdict
