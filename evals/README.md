# Evals

End-to-end evals for the crew (#325): real tasks on a small Optimizely CMS 13 site, graded on
the result. They exist to decide **roster changes**, such as folding one worker into another,
by score rather than by reading prompts. They are not part of CI: a run costs real tokens and
minutes.

## Layout

- `fixture/`: the site every run starts from. `src/EvalSite` (.NET 10, `EPiServer.CMS` 13.x,
  Razor views), `tests/EvalSite.Tests` (xUnit, NSubstitute), its `.claude/crew.md`, and a
  `docker-compose.yml` for the database. It carries two pieces of debt on purpose (tasks 07
  and 08).
- `tasks/<id>/`: `prompt.md` is what the session gets; `check.sh` grades the tree; optional
  `setup.sh` adds a commit before the session (the seeded regressions); optional `hidden/*.cs`
  are tests the session never sees, copied in at grading.
- `run.sh` runs tasks; `grade.sh` holds the criteria the checks share.

## Run

Needs the .NET 10 SDK, `claude`, `jq` and `git`, and the Optimizely NuGet feed
(`nuget.optimizely.com`, named in `fixture/nuget.config`).

```bash
evals/run.sh all                    # every task, twice
evals/run.sh -n 3 04-article-list-page
CREW_EVAL_PLUGIN=../crew-b/plugin evals/run.sh all   # the variant under test
```

Each run copies `fixture/` into `$TMPDIR/crew-evals/<stamp>/<task>-<n>/work` (`CREW_EVAL_OUT`
moves it; keep it outside any checkout, or the session reads that checkout's `CLAUDE.md` too),
makes it a git repo on
`main`, runs `setup.sh`, then `claude -p --agent crew:lead` with the prompt plus "Just build it."
(the standing go-ahead, so the plan checkpoint does not stop a headless run). The session gets
`acceptEdits` and a tool allow-list, never `--dangerously-skip-permissions`. `grade.log` has
one PASS or FAIL line per criterion; `summary.jsonl` has one line per run with the verdict, wall
time, turns, cost and tokens. Delete the results when done, since each work tree keeps its
build output.

The site does not run during an eval yet: every criterion reads the tree or runs the build,
test and lint gates. To run the site by hand, `docker compose up -d --wait` in `fixture/`, then
`dotnet run --project src/EvalSite`; the CMS creates its schema on the empty database, and
`/Optimizely/CMS` asks for the first admin user. The database has no content until someone
adds it, so `visual-review` has no page to measure.

## Tasks

| Task | Lane it should take | Graded on |
|---|---|---|
| 01-rename-teaser | express | `Summary` property, a `UsedToBeNamed("Teaser")` migration, no view on `.Teaser` |
| 02-article-date | express | a `<time>` with a `yyyy-MM-dd` `datetime` in the article view |
| 03-quote-block | feature | block type with a GUID, allowed on the start page, `<blockquote>` and `<cite>` |
| 04-article-list-page | feature | list page type, paging links, the session's own tests, hidden `GetPage` tests |
| 05-missing-teaser-job | feature | `ScheduledJobBase` with a GUID, tests that name the job |
| 06-breadcrumb | feature | `GetAncestors`, a breadcrumb `<nav>`, a new test file |
| 07-debt-service-locator | debt | no `ServiceLocator`, `IUrlResolver` by constructor |
| 08-debt-html-raw | debt | no `Html.Raw`, `MainBody` through `epi-property` or `PropertyFor` |
| 09-regression-oldest-first | regression | hidden ordering test |
| 10-regression-future-articles | regression | hidden future-date test |

Every task also needs: work committed on a feature branch, `main` untouched, a clean tree, and
green build, tests and lint. The lane column is what `lead` should pick; the grade does not
check it, so read the session when a lane matters to the comparison.

## What the scores decide

The evals inform roster changes only: whether an agent stays a subagent or folds into another
loop. The maintainer makes the call; the score is evidence, not a verdict.

- **Never** guards and safety rules (`lead` as sole git owner, `gitdir-guard`, the
  `bash-safety` refusals) or the conventions in `AGENTS.md`. A better score never removes one.
- **Compare one change at a time**, two variants on the same tasks and run count.
- **Ten tasks run twice is a small sample.** A gap of one or two tasks can be noise; an unclear
  result means no change.
- **Read every task that flipped**, not only the total. A fold can raise the total and still
  break a task that matters, such as the regression lane.

## Gaps

- A grep criterion can pass a wrong change or fail a right one with an unexpected shape (a
  quote block named `BlockquoteBlock`). Read `grade.log` before trusting a flip.
- Hidden tests pin `ArticleService`'s constructor and method signatures, so a session that
  changes them fails the hidden tests even when the behavior is right.
