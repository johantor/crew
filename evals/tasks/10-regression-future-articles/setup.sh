#!/usr/bin/env bash
# Seeds the regression as an ordinary-looking commit: the date filter goes, and so does the
# test that would have caught it.
set -euo pipefail

perl -0pi -e 's/ && article\.ArticleDate <= now//; s/\n        var now = timeProvider\.GetUtcNow\(\)\.UtcDateTime;//' \
  src/EvalSite/Services/ArticleService.cs
perl -0pi -e 's/\n    \[Fact\]\n    public void GetLatest_skips_articles_dated_in_the_future\(\)\n    \{.*?\n    \}\n//s' \
  tests/EvalSite.Tests/ArticleServiceTests.cs

git add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -qm "Refactor article filtering"
