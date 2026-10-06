#!/usr/bin/env bash
# Behavioral tests for hooks/lane-guard.sh.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="lane-guard.sh"

# --- No backend stack configured: backend/frontend have no lane -------------------
# The guard detects nothing. Which regime applies is pinned by /crew:init, so an
# unset stack is a refusal naming it, for a .cs and a .tsx alike.
assert_block "backend refused with no .claude/crew.md"  "$HOOK" "$(payload_file crew:backend Foo.cs)" "Run /crew:init"
assert_block "frontend refused with no .claude/crew.md" "$HOOK" "$(payload_file crew:frontend Foo.tsx)" "Run /crew:init"
fm_unset="$(make_crew_md 'backendStack: unset
frontendStack: unset
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "backend refused while backendStack is unset" \
  "$HOOK" "$(payload_file crew:backend Foo.cs)" "Run /crew:init" "$fm_unset"
# Lane paths alone do not stand in for the stack: the refusal comes first.
fm_paths_only="$(make_crew_md 'backendStack: unset
frontendStack: unset
backendLanePaths: src/api
frontendLanePaths: src/web')"
assert_block "backend refused with lane paths but no backendStack" \
  "$HOOK" "$(payload_file crew:backend src/api/Foo.cs)" "Run /crew:init" "$fm_paths_only"
# unit-tests's lane is the union of test conventions and needs no stack.
assert_allow "unit-tests keeps its lane with no .claude/crew.md" "$HOOK" "$(payload_file crew:unit-tests src/foo.test.ts)"

# --- Extension regime (a backend whose extensions differ from the frontend's) ---
fm_ext="$(make_crew_md 'backendStack: dotnet
frontendStack: react')"
assert_block "backend denied a .tsx file"   "$HOOK" "$(payload_file crew:backend Foo.tsx)"  "out of" "$fm_ext"
assert_allow "backend allowed a .cs file"   "$HOOK" "$(payload_file crew:backend Foo.cs)" "$fm_ext"
# An installed plugin's worker calls tools as `crew:backend`; another plugin's
# `backend` is not this crew's and gets no lane.
assert_block "crew:backend denied a .tsx file" "$HOOK" "$(payload_file crew:backend Foo.tsx)" "out of" "$fm_ext"
assert_allow "crew:backend allowed a .cs file" "$HOOK" "$(payload_file crew:backend Foo.cs)" "$fm_ext"
assert_allow "other:backend has no lane here"  "$HOOK" "$(payload_file other:backend Foo.tsx)" "$fm_ext"
assert_allow "a project's bare backend agent is not refused for crew's unset stack" \
  "$HOOK" "$(payload_file backend Foo.cs)" "$fm_unset"
assert_block "frontend denied a .cs file" "$HOOK" "$(payload_file crew:frontend Foo.cs)" "out of" "$fm_ext"
assert_allow "frontend allowed a .tsx file" "$HOOK" "$(payload_file crew:frontend Foo.tsx)" "$fm_ext"

# --- Extension regime, the Python/Go/Rust/JVM backends -------------------------
# These extensions are disjoint from the frontend's, so the stacks need no lane
# paths. A miss fails silently in production: the guard passes, the lanes don't.
for _f in svc.py svc.pyi pyproject.toml requirements.txt setup.py setup.cfg \
          tox.ini Pipfile poetry.lock uv.lock pdm.lock \
          mypy.ini pyrightconfig.json pytest.ini ruff.toml .flake8 .golangci.yml \
          rustfmt.toml clippy.toml \
          svc.go go.mod go.sum go.work go.work.sum \
          svc.rs Cargo.toml Cargo.lock \
          Svc.java pom.xml build.gradle build.gradle.kts settings.gradle gradle.properties \
          gradle/libs.versions.toml gradle/wrapper/gradle-wrapper.properties \
          run.sh lib.bash .shellcheckrc \
          pkg/testdata/golden.json src/test/resources/fixture.sql src/test/fixtures/data.json \
          src/main/resources/application.yml svc/src/main/resources/application-prod.properties; do
  assert_block "frontend denied a backend file ($_f)" "$HOOK" "$(payload_file crew:frontend "$_f")" "out of" "$fm_ext"
  assert_allow "backend allowed a backend file ($_f)"   "$HOOK" "$(payload_file crew:backend "$_f")" "$fm_ext"
done
# The union is per-extension, not per-resolved-stack: a pinned Python backend
# still denies frontend a .rs file. Pinning a stack must not widen frontend's lane.
fm_python="$(make_crew_md 'backendStack: python
frontendStack: react')"
assert_block "frontend denied .rs under a pinned python backend" \
  "$HOOK" "$(payload_file crew:frontend svc.rs)" "out of" "$fm_python"
assert_allow "frontend keeps repo-wide .editorconfig" "$HOOK" "$(payload_file crew:frontend .editorconfig)" "$fm_ext"
# The view half of src/main/resources stays frontend's, like .cshtml.
assert_allow "frontend keeps a Thymeleaf template" \
  "$HOOK" "$(payload_file crew:frontend src/main/resources/templates/index.html)" "$fm_ext"
assert_allow "frontend keeps Spring's static assets" \
  "$HOOK" "$(payload_file crew:frontend src/main/resources/static/app.css)" "$fm_ext"
assert_allow "frontend still allowed a .tsx under a pinned python backend" \
  "$HOOK" "$(payload_file crew:frontend Foo.tsx)" "$fm_python"

# --- unit-tests / e2e confined to test paths ------------------------------------
assert_allow "unit-tests allowed a unit test"     "$HOOK" "$(payload_file crew:unit-tests src/foo.test.ts)"
assert_block "unit-tests denied a non-test file"  "$HOOK" "$(payload_file crew:unit-tests src/foo.ts)" "allowed paths"
assert_block "unit-tests denied an e2e spec (e2e's lane)" "$HOOK" "$(payload_file crew:unit-tests e2e/foo.spec.ts)" "e2e lane"
# One assertion per test convention in unit-tests's allow list.
for _t in pkg/test_svc.py pkg/testservice.py pkg/svc_test.py pkg/conftest.py \
          pkg/svc_test.go pkg/testdata/input.json \
          tests/integration.rs \
          src/test/java/com/example/SvcTest.java app/src/test/resources/fixture.sql \
          tests/guard.bats plugins/crew/tests/lane-guard.test.sh; do
  assert_allow "unit-tests allowed a test path ($_t)" "$HOOK" "$(payload_file crew:unit-tests "$_t")"
done
# Every Surefire/Failsafe convention, including outside src/test.
for _j in SvcTest.java TestSvc.java SvcTests.java SvcTestCase.java SvcIT.java ITSvc.java SvcITCase.java; do
  assert_allow "unit-tests allowed a JUnit class ($_j)" "$HOOK" "$(payload_file crew:unit-tests "$_j")"
done
# Production code in those same ecosystems stays out of unit-tests's lane.
for _p in pkg/svc.py pkg/svc.go src/lib.rs src/main/java/com/example/Svc.java; do
  assert_block "unit-tests denied production code ($_p)" "$HOOK" "$(payload_file crew:unit-tests "$_p")" "allowed paths"
done
assert_allow "e2e allowed an e2e spec"      "$HOOK" "$(payload_file crew:e2e e2e/foo.spec.ts)"
assert_block "e2e denied a source file"     "$HOOK" "$(payload_file crew:e2e src/foo.ts)" "allowed paths"

# --- lead writes plans, ledgers and tickets only ----------------------------
# The orchestrator never edits production code. Its Edit/Write lane is a filename
# shape at any depth (plan-*.md, debt-*.md, crew.md, agent-memory/**,
# tickets/*.md) plus scratch, whether the path is repo-relative or absolute, and whatever the plan
# directory is configured as -- so there is no directory to anchor or to overlap.
assert_allow "lead allowed a plan file"           "$HOOK" "$(payload_file crew:lead .claude/plan-sso.md)"
assert_allow "lead allowed a debt ledger"         "$HOOK" "$(payload_file crew:lead .claude/debt-cs8602.md)"
assert_allow "lead allowed a plan in another plan directory" "$HOOK" "$(payload_file crew:lead docs/plans/plan-sso.md)"
assert_allow "lead allowed a plan at the repo root" "$HOOK" "$(payload_file crew:lead plan-sso.md)"
assert_allow "lead allowed crew config"           "$HOOK" "$(payload_file crew:lead .claude/crew.md)"
assert_allow "lead allowed its local agent memory" "$HOOK" "$(payload_file crew:lead .claude/agent-memory-local/lead/MEMORY.md)"
assert_allow "lead allowed project agent memory (absolute)" "$HOOK" "$(payload_file crew:lead /repo/.claude/agent-memory/lead/MEMORY.md)"
assert_allow "lead allowed scratch under /tmp"    "$HOOK" "$(payload_file crew:lead /tmp/crew/outline.md)"
assert_block "lead denied a source file"          "$HOOK" "$(payload_file crew:lead src/app.ts)" "allowed paths"
assert_block "lead denied a test file"            "$HOOK" "$(payload_file crew:lead tests/app.test.ts)" "allowed paths"
assert_block "lead denied source under a nested .claude directory" \
  "$HOOK" "$(payload_file crew:lead src/.claude/app.ts)" "allowed paths"
assert_block "lead denied a Markdown file that is not a plan or ledger" \
  "$HOOK" "$(payload_file crew:lead README.md)" "allowed paths"
assert_block "lead denied a plan-named source file" \
  "$HOOK" "$(payload_file crew:lead src/plan-runner.ts)" "allowed paths"
assert_block "lead denied source under a lookalike memory directory" \
  "$HOOK" "$(payload_file crew:lead src/agent-memory-local/app.ts)" "allowed paths"
# A configured plan directory changes nothing: the lane is the shape, not the place.
fm_src="$(make_crew_md 'planDirectory: src')"
assert_allow "lead allowed a plan in a plan directory set to src" \
  "$HOOK" "$(payload_file crew:lead src/plan-sso.md)" "$fm_src"
assert_block "lead denied source in a plan directory set to src" \
  "$HOOK" "$(payload_file crew:lead src/app.ts)" "allowed paths" "$fm_src"
# Ticket drafts are Markdown under a tickets/ directory, at any depth.
assert_allow "lead allowed a ticket draft" "$HOOK" "$(payload_file crew:lead .azuredevops/tickets/21132.md)"
assert_allow "lead allowed a root ticket"  "$HOOK" "$(payload_file crew:lead tickets/21132.md)"
assert_block "lead denied a non-Markdown file under tickets/" \
  "$HOOK" "$(payload_file crew:lead src/tickets/Ticket.cs)" "allowed paths"
assert_block "lead denied a lookalike tickets directory" \
  "$HOOK" "$(payload_file crew:lead src/mytickets/x.md)" "allowed paths"
# Outside the project, lead writes anything (a session scratchpad, an az input
# file); the check is bash-safety's guard_outside_project, so it fails closed.
export CLAUDE_PROJECT_DIR=/home/dev/proj
assert_allow "lead allowed a scratchpad outside the project" \
  "$HOOK" "$(payload_file crew:lead /home/dev/scratch/session/description.html)"
assert_block "lead denied an absolute source path in the project" \
  "$HOOK" "$(payload_file crew:lead /home/dev/proj/src/app.ts)" "allowed paths"
assert_block "lead denied an absolute path in the project, other case" \
  "$HOOK" "$(payload_file crew:lead /HOME/dev/Proj/src/app.ts)" "allowed paths"
assert_block "lead denied a hidden segment outside the project" \
  "$HOOK" "$(payload_file crew:lead /home/dev/.ssh/config)" "allowed paths"
CLAUDE_PROJECT_DIR='C:\work\proj'
export CREW_OSTYPE=msys
assert_allow "lead allowed a Windows temp scratchpad" \
  "$HOOK" "$(payload_file crew:lead 'C:\Users\dev\AppData\Local\Temp\claude\description.html')"
assert_block "lead denied a Windows path in the project" \
  "$HOOK" "$(payload_file crew:lead 'C:\work\proj\src\App.cs')" "allowed paths"
# The harness hands a Windows hook backslash paths; the lane globs use `/`.
assert_allow "lead allowed a Windows plan path in the project" \
  "$HOOK" "$(payload_file crew:lead 'C:\work\proj\.claude\plan-sso.md')"
assert_allow "lead allowed a Windows agent-memory path in the project" \
  "$HOOK" "$(payload_file crew:lead 'C:\work\proj\.claude\agent-memory-local\lead\notes.md')"
assert_allow "lead allowed a relative Windows plan path" \
  "$HOOK" "$(payload_file crew:lead '.claude\plan-sso.md')"
assert_block "lead denied a Windows '..' traversal" \
  "$HOOK" "$(payload_file crew:lead 'C:\work\proj\.claude\..\src\plan-x.md')" "'..' segment"
assert_allow "unit-tests allowed a Windows test path" \
  "$HOOK" "$(payload_file crew:unit-tests 'C:\work\proj\tests\Foo.Tests\FooTests.cs')"
# A drive-relative path resolves against a directory the guard cannot see.
assert_block "unit-tests denied a drive-relative '..' path" \
  "$HOOK" "$(payload_file crew:unit-tests 'C:..\tests\Foo.test.ts')" "drive-relative"
assert_block "unit-tests denied a drive-relative path" \
  "$HOOK" "$(payload_file crew:unit-tests 'C:tests\Foo.test.ts')" "drive-relative"
# Cygwin spells the project root `/cygdrive/c/...`; a native path is still inside it.
CLAUDE_PROJECT_DIR=/cygdrive/c/work/proj CREW_OSTYPE=cygwin
assert_block "lead denied a Windows path inside a Cygwin project root" \
  "$HOOK" "$(payload_file crew:lead 'C:\work\proj\src\App.cs')" "allowed paths"
unset CLAUDE_PROJECT_DIR CREW_OSTYPE
assert_block "lead denied an absolute path with no project dir" \
  "$HOOK" "$(payload_file crew:lead /home/dev/scratch/description.html)" "allowed paths"

# --- A `..` segment is refused for every lane agent -----------------------------
assert_block "lead denied a '..' traversal out of .claude" \
  "$HOOK" "$(payload_file crew:lead .claude/../src/app.ts)" "'..' segment"
assert_block "unit-tests denied a '..' traversal out of tests/" \
  "$HOOK" "$(payload_file crew:unit-tests tests/../src/foo.ts)" "'..' segment"
assert_block "backend denied a '..' traversal (checked before any lane regime)" \
  "$HOOK" "$(payload_file crew:backend src/api/../web/page.ts)" "'..' segment" "$fm_ext"
assert_block "lead denied a leading '..'" \
  "$HOOK" "$(payload_file crew:lead ../other/.claude/plan-x.md)" "'..' segment"
assert_allow "'..' inside a filename is not a segment" \
  "$HOOK" "$(payload_file crew:lead .claude/plan-v1..2.md)"

# --- Agents with no lane ------------------------------------------------------
assert_allow "debt-scout has no Edit/Write tool; the hook never fires for it" "$HOOK" "$(payload_file crew:debt-scout Foo.tsx)"
assert_allow "visual-review has no write lane restriction" "$HOOK" "$(payload_file crew:visual-review Foo.tsx)"
assert_allow "generalist (express) is unrestricted"        "$HOOK" "$(payload_file crew:generalist Foo.tsx)"
assert_allow "no agent_type is unrestricted"        "$HOOK" "$(jq -nc --arg f Foo.tsx '{tool_input: {file_path: $f}}')"

# --- Same-language (Node) ambiguity, configured in .claude/crew.md ------------
# The current source of configuration: YAML frontmatter, one key per slot.
fm_node_fe="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "frontmatter: node backend + frontend, no lane paths → fail closed" \
  "$HOOK" "$(payload_file crew:backend src/app.ts)" "can't tell them apart" "$fm_node_fe"

fm_both="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web')"
assert_allow "frontmatter: backend allowed in its backend lane" \
  "$HOOK" "$(payload_file crew:backend src/api/handler.ts)" "$fm_both"
assert_block "frontmatter: backend denied in the frontend lane" \
  "$HOOK" "$(payload_file crew:backend src/web/page.ts)" "out of" "$fm_both"
export CREW_OSTYPE=msys
assert_block "frontmatter: backend denied a Windows path in the frontend lane" \
  "$HOOK" "$(payload_file crew:backend 'C:\work\proj\src\web\page.ts')" "out of" "$fm_both"
unset CREW_OSTYPE

fm_one="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: unset')"
assert_block "frontmatter: only one lane path configured → fail closed" \
  "$HOOK" "$(payload_file crew:backend src/api/handler.ts)" "only one of" "$fm_one"

# A quoted YAML scalar is the same value. Left unstripped it would build the glob
# `"src/api"/**`, which matches nothing, so backend would be silently unconfined.
fm_quoted="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: "src/api"
frontendLanePaths: '"'"'src/web'"'"'')"
# A .cs path is the discriminator here and in the two cases below: the extension
# regime backend falls back to when a lane path is unreadable leaves .cs alone, so
# only a real lane blocks this. An unreadable lane path fails *open* — the glob
# matches nothing, which reads as no lane at all.
assert_block "frontmatter: quoted lane paths still confine backend" \
  "$HOOK" "$(payload_file crew:backend src/web/page.cs)" "out of" "$fm_quoted"

# A YAML inline comment is not part of the value. /crew:init writes none, but the
# file is hand-editable.
fm_comment="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api # the service
frontendLanePaths: "src/web" # the app')"
assert_block "frontmatter: an inline comment is not part of the lane path" \
  "$HOOK" "$(payload_file crew:backend src/web/page.cs)" "out of" "$fm_comment"

# ...but a `#` with no whitespace before it is an ordinary scalar character, so
# the comment scan must anchor on the space rather than on the first `#`.
fm_hash="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api#2
frontendLanePaths: src/web#2')"
assert_block "frontmatter: a bare # stays part of the lane path" \
  "$HOOK" "$(payload_file crew:backend 'src/web#2/page.cs')" "out of" "$fm_hash"

# The body below the frontmatter is free prose and may quote an example block —
# /crew:init's own §1 does. A key matched there is not configuration.
fm_body="$(make_crew_md 'backendStack: dotnet
frontendStack: react
backendLanePaths: unset
frontendLanePaths: unset' 'An example of what this file can hold:

```markdown
backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web
```')"
# Again .cs: a leaked frontendLanePaths would put src/web out of backend's reach,
# while the extension regime the unset slots really mean leaves .cs to backend.
assert_allow "frontmatter: a slot quoted in the body is not read" \
  "$HOOK" "$(payload_file crew:backend src/web/handler.cs)" "$fm_body"

# e2e: playwright widens to tests/**, and the frontend lane confines it there.
fm_e2e="$(make_crew_md 'frontendE2eTool: playwright
frontendLanePaths: apps/web')"
assert_allow "frontmatter: e2e allowed an e2e spec inside its frontend lane" \
  "$HOOK" "$(payload_file crew:e2e apps/web/tests/checkout.spec.ts)" "$fm_e2e"
assert_block "frontmatter: e2e denied an e2e spec outside its frontend lane" \
  "$HOOK" "$(payload_file crew:e2e apps/api/tests/checkout.spec.ts)" "outside" "$fm_e2e"

# --- Retired config locations are not read (5.0.0, #248) -----------------------
# A legacy `## Crew configuration` block in CLAUDE.md and the `--local` crew.md in
# the git dir both used to configure lanes. Neither may: each fixture below puts
# src/web in backend's lane and src/api out of it, so if it were read backend's .tsx
# under src/web would pass and its .cs under src/api would be blocked. The
# extension regime's verdicts (from the real .claude/crew.md) prove the file was
# ignored.
stale_block="$(make_tree 'CLAUDE.md:- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/web
- **Frontend lane path(s):** src/api' '.claude/crew.md:---
backendStack: dotnet
frontendStack: react
---')"
assert_block "a legacy CLAUDE.md block no longer configures lanes" \
  "$HOOK" "$(payload_file crew:backend src/web/Foo.tsx)" "out of" "$stale_block"
assert_allow "a legacy CLAUDE.md block no longer confines backend" \
  "$HOOK" "$(payload_file crew:backend src/api/Foo.cs)" "$stale_block"

local_clone="$(make_git_branch main)"
printf '%s\n' '---
backendStack: node
frontendStack: nextjs
backendLanePaths: src/web
frontendLanePaths: src/api
---' > "$local_clone/.git/crew.md"
mkdir -p "$local_clone/.claude"
printf '%s\n' '---
backendStack: dotnet
frontendStack: react
---' > "$local_clone/.claude/crew.md"
assert_allow "a crew.md in the git dir no longer confines backend" \
  "$HOOK" "$(payload_file crew:backend src/api/Foo.cs)" "$local_clone"

# --- The guard detects nothing (7.0.0) -----------------------------------------
# Repo markers that used to select the regime are ignored: a Node backend beside
# a frontend with no stack configured is the same refusal as an empty cwd, not a
# probed verdict, and a .NET project does not switch an unset stack to extensions.
node_react="$(make_tree 'package.json:{"dependencies":{"express":"^4","react":"^18"}}')"
assert_block "markers do not stand in for an unset stack" \
  "$HOOK" "$(payload_file crew:backend src/app.ts)" "Run /crew:init" "$node_react"
mixed="$(make_tree 'Api.csproj:<Project />' 'package.json:{"dependencies":{"express":"^4"}}')"
assert_block "a .csproj does not switch an unset stack to extensions" \
  "$HOOK" "$(payload_file crew:backend Api/Foo.cs)" "Run /crew:init" "$mixed"

finish
