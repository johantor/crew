---
name: debt-taxonomy
description: Stack-neutral core for crew's debt lane — stack detection, classification rubric, blast-radius gate, upgrade tiers, batch commit shape, and handoff-outline format. Pairs with a per-stack taxonomy skill (debt-taxonomy-dotnet, debt-taxonomy-typescript). Loaded by the `debt-lane` skill.
---

# Debt taxonomy (core)

This is the stack-neutral core. The suppression mechanisms, package-manager variance, and
upgrade examples for a specific stack live in that stack's skill:

- **.NET / C#** → `debt-taxonomy-dotnet`
- **TypeScript / JavaScript** (React frontend or Node backend/CLI) → `debt-taxonomy-typescript`

## Stack detection

Before enumerating or classifying, detect the stack(s) in scope with a single marker-file
pass — do not assume. Apply the matching per-stack skill for each detected stack.

| Marker file(s) | Stack | Skill to apply |
|---|---|---|
| `*.csproj`, `*.sln`, `Directory.Packages.props`, `Directory.Build.props`, `global.json` | .NET / C# | `debt-taxonomy-dotnet` |
| `package.json`, `tsconfig.json`, `.eslintrc*`, `biome.json` | TypeScript / JS | `debt-taxonomy-typescript` |

```bash
# One pass — presence only, no file bodies
ls *.sln Directory.Packages.props Directory.Build.props global.json 2>/dev/null
find . -maxdepth 3 \( -name '*.csproj' -o -name 'package.json' -o -name 'tsconfig.json' \
  -o -name '.eslintrc*' -o -name 'biome.json' \) 2>/dev/null | head
```

A repo may match more than one stack (a typical Optimizely + React solution matches both) —
that is expected; apply each stack's skill to its own lane.

**Lanes are not stacks.** A lane (`backend`/`frontend`) names a *file area* used for scoping
and delegation; a stack names a *language*. Never infer the taxonomy from the lane name — a
`backend` lane is C# in an Optimizely repo but TypeScript in a Node repo. The skill applied to
a file always comes from the marker-file detection above, regardless of which lane the file
sits in.

**If no stack matches** (Go, Python, Java, Rust, etc.): say so plainly, report what marker
files you *did* find, and ask the user for the suppression mechanism rather than guessing.
Do not attempt to fix a stack with no taxonomy here — a wrong suppression edit is
worse than no edit. (Adding a stack is a small additive change: a new `debt-taxonomy-<stack>`
skill plus a row in the table above.)

## Upgrade tiers and risk (stack-neutral shapes)

One table decides both the tier (pointer or project) and the verification gate:

| Pointer shape | Risk | Tier | Verification gate |
|---|---|---|---|
| Single package, patch (`x.y.Z`) | SAFE | 1 | behavior-preserving — build/lint clean is sufficient |
| Single package, minor (`x.Y.z`) | REVIEW | 1 | behavior-sensitive — read release notes; **tests-green** |
| Single package, major (`X.y.z`) | CAUTION | 1 | behavior-sensitive — migration notes required; **tests-green** |
| Multi-package coordinated bump | the largest delta's | 1 if same lane, **2** if cross-lane | the delta's gate, or outline |
| Framework/platform version (TFM, runtime major, framework major) | CAUTION | **2** | outline only |
| Toolchain replacement (bundler, compiler) | CAUTION | **2** | outline only |

Treat pre-1.0 (`0.y.z`) bumps as one risk level higher (a `0.minor` can break like a major).
Concrete per-stack examples (EF Core, React, .NET TFM, Node major) live in the stack skills.

**The rule:** a version bump is a pointer; a platform migration is a project. The debt lane
fixes pointers. It outlines projects and hands them to the full flow.

## Upgrade workflow (stack-neutral)

The steps below name **no** package manager — every concrete command (discover, apply,
lockfile, conflict signal, release-notes URL) comes from the loaded `debt-taxonomy-<stack>`
skill's package-manager table. This is what keeps upgrades package-manager-agnostic: npm /
yarn / pnpm / NuGet today, and a new manager is one row in that table.

1. **Risk triage** by the table above, from the `current → target` delta.
2. **Release notes for non-patch.** For REVIEW/CAUTION, pull the change/migration notes
   **before** applying — prefer Context7 (`mcp__context7`); fall back to the package's release
   page (the per-stack skill resolves the URL). Surface concrete breaking changes that touch
   this codebase (grep the affected APIs) — not a generic changelog dump (`context-discipline`).
3. **Apply** using the per-stack command, and **commit the matching lockfile/manifest** in the
   same batch.
4. **Peer / transitive conflicts → stop.** When the manager reports a peer or transitive
   conflict (signal named per stack), report it and stop — never silently force, downgrade-pin,
   or pass an override flag.
5. **Verify** with the configured build/test command (tests-green for non-patch). On failure,
   **revert the single offending package** to its prior version (targeted, not a blanket
   rollback) and report what broke.

A multi-package coordinated bump follows the same steps as one batch; cross-lane coordination
or a framework major is tier 2 — outline, don't apply.

## Stale-suppression heuristic (audit `stale` scope)

The `/crew:audit stale` scope fans out across every suppression mechanism each loaded
per-stack skill declares, filtered to suppressions that look removable. Audit is grep-only
(`context-discipline`) — true staleness requires a compile, which is too expensive for a
scout pass. So `stale` reports **candidates**; final proof is left to `/crew:debt`,
where a worker can compile/build and confirm.

Each `debt-taxonomy-<stack>` skill declares, per mechanism, a **grep-only stale signal** — a
textual sign that the suppression is likely removable without reading the diagnostic state.
Rule of thumb when authoring one: it must be checkable from a `grep`/`rg` invocation alone,
with no parser, no compiler, no AST.

Findings from `stale` scope are classified through the same rubric as any other audit —
typically rubric class 2 (trivially fixable) and behavior-preserving — and ranked the same
way. Every finding still emits a ready-to-paste `/crew:debt <pointer>` so the user can
ask a worker to prove the candidate stale and remove it.

## Classification rubric

Classify every suppression *before* gating. Applied in order:

1. **Legitimately suppressed** — has a meaningful justification comment/param AND the issue it suppresses is a known false-positive or intentional pattern. Action: add or verify justification; leave the suppression; remove from backlog.
2. **Trivially fixable** — suppression is stale (the diagnostic no longer fires at that location) OR the fix is a one-line code change (rename, null-check, cast). Action: remove suppression and/or apply fix; verify.
3. **Needs real work** — fix requires design judgment, non-trivial refactor, or understanding of business logic. Action: include in batch with explicit acceptance criteria; the lane's worker implements.
4. **Needs investigation** — skipped tests, blanket suppressions without context, any suppression with no commit rationale and an unclear rule. Action: `git log -1 --format="%s %ae %ar" -- <file>` to surface committer/date; flag in report; do not auto-fix.
5. **Environmental** — suppresses a tooling/build-environment quirk not fixable in application code (generated code, vendored files, CI-only paths). Action: mark legitimate; suggest a justification.

## Justified suppressions — what audit skips

A suppression the team already decided to keep should not be re-surfaced every audit. The debt
lane **reads** justifications; it never writes or demands them. There is no ack command and no
crew-specific syntax: the justification is whatever the developer wrote in the mechanism's
**own** justification slot when they wrote the suppression. Each `debt-taxonomy-<stack>` skill
declares that slot per mechanism, and names the mechanisms that have none.

**What counts as a justification.** Grep-checkable only — audit never compiles:

- The mechanism's native slot is present and carries **at least two words**, and
- the text is not *solely* a deferral marker: `TODO`, `FIXME`, `HACK`, `XXX`, `WIP`,
  `fix later`, `temporary`, `for now`, `n/a`, `-`, `?`, `see above`.

A deferral marker says the debt is still owed — the opposite of a keep-decision.

This is a **heuristic, not a guarantee**: two words of genuine nonsense ("needed here") passes it,
and a terse-but-real reason may read as thin. It is calibrated to be cheap and grep-only, so it
will misjudge in both directions. That is why the bias is fixed: **when it is ambiguous, surface
the finding.** Excluding one hides debt, and a re-surfaced suppression costs a glance whereas a
hidden one costs nothing until it matters.

**Effect on the report.** A justified suppression classifies **rubric class 1** and is excluded
from the ranked report, but **still counted in totals** — e.g. `14 findings (3 justified,
excluded)` — so the debt is never silently invisible. This formalizes class 1's existing
"verify justification; leave the suppression; remove from backlog" action.

**Scope exemptions — the filter does not apply everywhere:**

| Audit scope | Justification filter |
|---|---|
| path, lane, rule family, `diff` | **Applies** — justified findings excluded from the report, counted in totals |
| `stale` | **Does not apply.** Staleness is orthogonal to legitimacy: a justified suppression whose diagnostic no longer fires is still removable, and the justification explains why it was *added*, not why it should stay now. Justified candidates are listed, tagged `justified` |
| `outdated` | Not applicable — no suppressions involved |

**Skipped tests are never excluded by this filter.** A `Skip="…"` reason or an `it.skip`
comment is not a legitimacy justification; skipped tests stay **rubric class 4**
(needs-investigation) and stay in the report however they are annotated.

**`open` respects it too.** When *every* site a pointer resolves to carries a justification,
`/crew:debt` exits with a one-liner quoting the rationale — same shape as the 0-findings
exit — and `--force` (a **`/crew:debt`-only** flag; audit has no override, it lists exclusions instead)
overrides to work it anyway. When only *some* sites are justified, proceed
with the rest and note the excluded count; a partly-justified rule is still real work.

**Rule- or path-level policy belongs in the project's own `AGENTS.md`/`CLAUDE.md`** — a coarse
standing decision ("we don't chase `no-explicit-any` under `src/legacy/**` — scheduled for
deletion") is one prose statement rather than fifty annotations. Honor such a section's
exclusions and report them in the totals. No section → exclude nothing on that basis; unclear
intent → surface the finding and say the policy was ambiguous rather than guessing.

## Behavior sensitivity (orthogonal to the rubric)

Independently of the rubric class, tag every finding as **behavior-preserving** or
**behavior-sensitive** — they need different verification:

- **Behavior-preserving** — the fix cannot change runtime behavior: type-only changes, unused-symbol removal, formatting, stale suppressions whose diagnostic no longer fires. For these, "compiler/linter clean" is a **sufficient** acceptance gate.
- **Behavior-sensitive** — the fix moves, adds, or reorders runtime logic, so a green linter does **not** prove correctness. For these, the acceptance gate **must be "tests green," not "lint clean."** Examples are tagged per stack (see the stack skills) — e.g. React hook placement/dependency rules.

Which rules are behavior-sensitive is listed in each per-stack skill. When in doubt, treat a
finding as behavior-sensitive — the cost of an unnecessary test run is far below the cost of a
silent behavior regression.

## Blast-radius gate

Enumerate with scripts — counts and file paths, never file bodies (`context-discipline`).
Then apply the gate:

- **≤ 5 findings, single lane** → proceed immediately (one worker, one commit)
- **6–40 findings, single lane** → proceed in batches (fan workers by directory cluster)
- **6–40 findings, cross-lane** → one background worker per lane, parallel dispatch
- **> 40 findings for a single rule** → stop, present natural slices (by directory/project), ask user which to proceed with; remainder becomes an open item or handoff outline on request
- **Platform migration detected** → classify as tier 2; produce handoff outline on user request; stop
- **Behavior-sensitive findings with no test command configured** → warn the user explicitly ("these change runtime behavior and no test suite is configured — a green linter won't catch a regression") and require acknowledgement before proceeding. This is the same warning the upgrade path gives; it applies to any behavior-sensitive batch, not just upgrades.

Behavior-sensitive batches commit **one logical unit per commit** (e.g. one component per
commit for a hook-placement fix) so a behavior regression stays bisectable — don't bundle
eight restructured components into one commit.

A project-wide suppression (one config line, repo-wide effect) must be expanded to its
**diagnostic count**, not its line count, before gating.

## Batch commit shape

One commit per rule/batch (bisectable). Message shape:
`chore(debt): remove CS8602 suppression in src/Orders/ (4 sites)`. Always delete the
suppression after the fix verifies — never leave both the fix and the suppression in place.

## Handoff outline format (tier-2 projects only)

Written to `<plan-dir>/plan-<slug>.md`, so a slice can feed `/crew:feature` directly.

```markdown
# <Migration name> — handoff outline

## Scope
<What this migration is and why it was classified as a project.>

## Blast radius (evidence)
- Backend: <count> call sites across <N> files in <projects>
- Frontend: <count> issues across <N> files
- Cross-cutting: <shared contracts, config files, or build pipeline changes>

## Work packages

### WP1: <name> (independent)
Acceptance criteria:
- <verifiable gate, e.g. "project X compiles against v5 with no errors">
Files in scope: <directory clusters>
Lane: backend | frontend | both
Open questions: <unknowns — do not guess>

### WP2: <name> (depends-on: WP1)
...

## Verification
Build / Test / Lint commands: <from crew configuration — the file they were read from>

## Known risks
<list; mark each UNKNOWN if unconfirmed>

## Open questions
<must be resolved before any WP starts>
```
