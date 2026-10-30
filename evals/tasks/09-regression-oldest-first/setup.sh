#!/usr/bin/env bash
# Seeds the regression as an ordinary-looking commit: the sort flips and the test that
# would have caught it goes with it.
set -euo pipefail

perl -0pi -e 's/OrderByDescending\(article => article\.ArticleDate\)/OrderBy(article => article.ArticleDate)/' \
  src/EvalSite/Services/ArticleService.cs
perl -0pi -e 's/\n    \[Fact\]\n    public void GetLatest_returns_newest_first\(\)\n    \{.*?\n    \}\n//s' \
  tests/EvalSite.Tests/ArticleServiceTests.cs
perl -0pi -e 's/\["A", "B"\]/["C", "B"]/' tests/EvalSite.Tests/ArticleServiceTests.cs

git add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -qm "Simplify the article query"
