#!/usr/bin/env bash
# Behavioral tests for hooks/lane-guard.sh.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="lane-guard.sh"

# --- No backend stack configured: tank/trinity have no lane -------------------
# The guard detects nothing. Which regime applies is pinned by /crew:init, so an
# unset stack is a refusal naming it, for a .cs and a .tsx alike.
assert_block "tank refused with no .claude/crew.md"  "$HOOK" "$(payload_file tank Foo.cs)" "Run /crew:init"
assert_block "trinity refused with no .claude/crew.md" "$HOOK" "$(payload_file trinity Foo.tsx)" "Run /crew:init"
fm_unset="$(make_crew_md 'backendStack: unset
frontendStack: unset
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "tank refused while backendStack is unset" \
  "$HOOK" "$(payload_file tank Foo.cs)" "Run /crew:init" "$fm_unset"
# oracle's lane is the union of test conventions and needs no stack.
assert_allow "oracle keeps its lane with no .claude/crew.md" "$HOOK" "$(payload_file oracle src/foo.test.ts)"

# --- Extension regime (a backend whose extensions differ from the frontend's) ---
fm_ext="$(make_crew_md 'backendStack: dotnet
frontendStack: react')"
assert_block "tank denied a .tsx file"   "$HOOK" "$(payload_file tank Foo.tsx)"  "out of" "$fm_ext"
assert_allow "tank allowed a .cs file"   "$HOOK" "$(payload_file tank Foo.cs)" "$fm_ext"
# An installed plugin's worker calls tools as `crew:tank`; another plugin's
# `tank` is not this crew's and gets no lane.
assert_block "crew:tank denied a .tsx file" "$HOOK" "$(payload_file crew:tank Foo.tsx)" "out of" "$fm_ext"
assert_allow "crew:tank allowed a .cs file" "$HOOK" "$(payload_file crew:tank Foo.cs)" "$fm_ext"
assert_allow "other:tank has no lane here"  "$HOOK" "$(payload_file other:tank Foo.tsx)" "$fm_ext"
assert_block "trinity denied a .cs file" "$HOOK" "$(payload_file trinity Foo.cs)" "out of" "$fm_ext"
assert_allow "trinity allowed a .tsx file" "$HOOK" "$(payload_file trinity Foo.tsx)" "$fm_ext"

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
  assert_block "trinity denied a backend file ($_f)" "$HOOK" "$(payload_file trinity "$_f")" "out of" "$fm_ext"
  assert_allow "tank allowed a backend file ($_f)"   "$HOOK" "$(payload_file tank "$_f")" "$fm_ext"
done
# The union is per-extension, not per-resolved-stack: a pinned Python backend
# still denies trinity a .rs file. Pinning a stack must not widen trinity's lane.
fm_python="$(make_crew_md 'backendStack: python
frontendStack: react')"
assert_block "trinity denied .rs under a pinned python backend" \
  "$HOOK" "$(payload_file trinity svc.rs)" "out of" "$fm_python"
assert_allow "trinity keeps repo-wide .editorconfig" "$HOOK" "$(payload_file trinity .editorconfig)" "$fm_ext"
# The view half of src/main/resources stays trinity's, like .cshtml.
assert_allow "trinity keeps a Thymeleaf template" \
  "$HOOK" "$(payload_file trinity src/main/resources/templates/index.html)" "$fm_ext"
assert_allow "trinity keeps Spring's static assets" \
  "$HOOK" "$(payload_file trinity src/main/resources/static/app.css)" "$fm_ext"
assert_allow "trinity still allowed a .tsx under a pinned python backend" \
  "$HOOK" "$(payload_file trinity Foo.tsx)" "$fm_python"

# --- oracle / dozer confined to test paths ------------------------------------
assert_allow "oracle allowed a unit test"     "$HOOK" "$(payload_file oracle src/foo.test.ts)"
assert_block "oracle denied a non-test file"  "$HOOK" "$(payload_file oracle src/foo.ts)" "allowed paths"
assert_block "oracle denied an e2e spec (dozer's lane)" "$HOOK" "$(payload_file oracle e2e/foo.spec.ts)" "e2e lane"
# One assertion per test convention in oracle's allow list.
for _t in pkg/test_svc.py pkg/testservice.py pkg/svc_test.py pkg/conftest.py \
          pkg/svc_test.go pkg/testdata/input.json \
          tests/integration.rs \
          src/test/java/com/example/SvcTest.java app/src/test/resources/fixture.sql \
          tests/guard.bats plugins/crew/tests/lane-guard.test.sh; do
  assert_allow "oracle allowed a test path ($_t)" "$HOOK" "$(payload_file oracle "$_t")"
done
# Every Surefire/Failsafe convention, including outside src/test.
for _j in SvcTest.java TestSvc.java SvcTests.java SvcTestCase.java SvcIT.java ITSvc.java SvcITCase.java; do
  assert_allow "oracle allowed a JUnit class ($_j)" "$HOOK" "$(payload_file oracle "$_j")"
done
# Production code in those same ecosystems stays out of oracle's lane.
for _p in pkg/svc.py pkg/svc.go src/lib.rs src/main/java/com/example/Svc.java; do
  assert_block "oracle denied production code ($_p)" "$HOOK" "$(payload_file oracle "$_p")" "allowed paths"
done
assert_allow "dozer allowed an e2e spec"      "$HOOK" "$(payload_file dozer e2e/foo.spec.ts)"
assert_block "dozer denied a source file"     "$HOOK" "$(payload_file dozer src/foo.ts)" "allowed paths"

# --- morpheus writes plans and ledgers only -----------------------------------
# The orchestrator never edits production code. Its Edit/Write lane is a filename
# shape at any depth (plan-*.md, debt-*.md, crew.md, agent-memory/**) plus
# scratch, whether the path is repo-relative or absolute, and whatever the plan
# directory is configured as -- so there is no directory to anchor or to overlap.
assert_allow "morpheus allowed a plan file"           "$HOOK" "$(payload_file morpheus .claude/plan-sso.md)"
assert_allow "morpheus allowed a debt ledger"         "$HOOK" "$(payload_file morpheus .claude/debt-cs8602.md)"
assert_allow "morpheus allowed a plan in another plan directory" "$HOOK" "$(payload_file morpheus docs/plans/plan-sso.md)"
assert_allow "morpheus allowed a plan at the repo root" "$HOOK" "$(payload_file morpheus plan-sso.md)"
assert_allow "morpheus allowed crew config"           "$HOOK" "$(payload_file morpheus .claude/crew.md)"
assert_allow "morpheus allowed its local agent memory" "$HOOK" "$(payload_file morpheus .claude/agent-memory-local/morpheus/MEMORY.md)"
assert_allow "morpheus allowed project agent memory (absolute)" "$HOOK" "$(payload_file morpheus /repo/.claude/agent-memory/morpheus/MEMORY.md)"
assert_allow "morpheus allowed scratch under /tmp"    "$HOOK" "$(payload_file morpheus /tmp/crew/outline.md)"
assert_block "morpheus denied a source file"          "$HOOK" "$(payload_file morpheus src/app.ts)" "allowed paths"
assert_block "morpheus denied a test file"            "$HOOK" "$(payload_file morpheus tests/app.test.ts)" "allowed paths"
assert_block "morpheus denied source under a nested .claude directory" \
  "$HOOK" "$(payload_file morpheus src/.claude/app.ts)" "allowed paths"
assert_block "morpheus denied a Markdown file that is not a plan or ledger" \
  "$HOOK" "$(payload_file morpheus README.md)" "allowed paths"
assert_block "morpheus denied a plan-named source file" \
  "$HOOK" "$(payload_file morpheus src/plan-runner.ts)" "allowed paths"
assert_block "morpheus denied source under a lookalike memory directory" \
  "$HOOK" "$(payload_file morpheus src/agent-memory-local/app.ts)" "allowed paths"
# A configured plan directory changes nothing: the lane is the shape, not the place.
fm_src="$(make_crew_md 'planDirectory: src')"
assert_allow "morpheus allowed a plan in a plan directory set to src" \
  "$HOOK" "$(payload_file morpheus src/plan-sso.md)" "$fm_src"
assert_block "morpheus denied source in a plan directory set to src" \
  "$HOOK" "$(payload_file morpheus src/app.ts)" "allowed paths" "$fm_src"

# --- A `..` segment is refused for every lane agent -----------------------------
assert_block "morpheus denied a '..' traversal out of .claude" \
  "$HOOK" "$(payload_file morpheus .claude/../src/app.ts)" "'..' segment"
assert_block "oracle denied a '..' traversal out of tests/" \
  "$HOOK" "$(payload_file oracle tests/../src/foo.ts)" "'..' segment"
assert_block "tank denied a '..' traversal (checked before any lane regime)" \
  "$HOOK" "$(payload_file tank src/api/../web/page.ts)" "'..' segment" "$fm_ext"
assert_block "morpheus denied a leading '..'" \
  "$HOOK" "$(payload_file morpheus ../other/.claude/plan-x.md)" "'..' segment"
assert_allow "'..' inside a filename is not a segment" \
  "$HOOK" "$(payload_file morpheus .claude/plan-v1..2.md)"

# --- Agents with no lane ------------------------------------------------------
assert_allow "keymaker has no Edit/Write tool; the hook never fires for it" "$HOOK" "$(payload_file keymaker Foo.tsx)"
assert_allow "seraph has no write lane restriction" "$HOOK" "$(payload_file seraph Foo.tsx)"
assert_allow "neo (express) is unrestricted"        "$HOOK" "$(payload_file neo Foo.tsx)"
assert_allow "no agent_type is unrestricted"        "$HOOK" "$(jq -nc --arg f Foo.tsx '{tool_input: {file_path: $f}}')"

# --- Same-language (Node) ambiguity, configured in .claude/crew.md ------------
# The current source of configuration: YAML frontmatter, one key per slot.
fm_node_fe="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "frontmatter: node backend + frontend, no lane paths → fail closed" \
  "$HOOK" "$(payload_file tank src/app.ts)" "can't tell them apart" "$fm_node_fe"

fm_both="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web')"
assert_allow "frontmatter: tank allowed in its backend lane" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "$fm_both"
assert_block "frontmatter: tank denied in the frontend lane" \
  "$HOOK" "$(payload_file tank src/web/page.ts)" "out of" "$fm_both"

fm_one="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: unset')"
assert_block "frontmatter: only one lane path configured → fail closed" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "only one of" "$fm_one"

# A quoted YAML scalar is the same value. Left unstripped it would build the glob
# `"src/api"/**`, which matches nothing, so tank would be silently unconfined.
fm_quoted="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: "src/api"
frontendLanePaths: '"'"'src/web'"'"'')"
# A .cs path is the discriminator here and in the two cases below: the extension
# regime tank falls back to when a lane path is unreadable leaves .cs alone, so
# only a real lane blocks this. An unreadable lane path fails *open* — the glob
# matches nothing, which reads as no lane at all.
assert_block "frontmatter: quoted lane paths still confine tank" \
  "$HOOK" "$(payload_file tank src/web/page.cs)" "out of" "$fm_quoted"

# A YAML inline comment is not part of the value. /crew:init writes none, but the
# file is hand-editable.
fm_comment="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api # the service
frontendLanePaths: "src/web" # the app')"
assert_block "frontmatter: an inline comment is not part of the lane path" \
  "$HOOK" "$(payload_file tank src/web/page.cs)" "out of" "$fm_comment"

# ...but a `#` with no whitespace before it is an ordinary scalar character, so
# the comment scan must anchor on the space rather than on the first `#`.
fm_hash="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api#2
frontendLanePaths: src/web#2')"
assert_block "frontmatter: a bare # stays part of the lane path" \
  "$HOOK" "$(payload_file tank 'src/web#2/page.cs')" "out of" "$fm_hash"

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
# Again .cs: a leaked frontendLanePaths would put src/web out of tank's reach,
# while the extension regime the unset slots really mean leaves .cs to tank.
assert_allow "frontmatter: a slot quoted in the body is not read" \
  "$HOOK" "$(payload_file tank src/web/handler.cs)" "$fm_body"

# dozer: playwright widens to tests/**, and the frontend lane confines it there.
fm_dozer="$(make_crew_md 'frontendE2eTool: playwright
frontendLanePaths: apps/web')"
assert_allow "frontmatter: dozer allowed an e2e spec inside its frontend lane" \
  "$HOOK" "$(payload_file dozer apps/web/tests/checkout.spec.ts)" "$fm_dozer"
assert_block "frontmatter: dozer denied an e2e spec outside its frontend lane" \
  "$HOOK" "$(payload_file dozer apps/api/tests/checkout.spec.ts)" "outside" "$fm_dozer"

# --- Retired config locations are not read (5.0.0, #248) -----------------------
# A legacy `## Crew configuration` block in CLAUDE.md and the `--local` crew.md in
# the git dir both used to configure lanes. Neither may: each fixture below puts
# src/web in tank's lane and src/api out of it, so if it were read tank's .tsx
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
  "$HOOK" "$(payload_file tank src/web/Foo.tsx)" "out of" "$stale_block"
assert_allow "a legacy CLAUDE.md block no longer confines tank" \
  "$HOOK" "$(payload_file tank src/api/Foo.cs)" "$stale_block"

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
assert_allow "a crew.md in the git dir no longer confines tank" \
  "$HOOK" "$(payload_file tank src/api/Foo.cs)" "$local_clone"

# --- The guard detects nothing (7.0.0) -----------------------------------------
# Repo markers that used to select the regime are ignored: a Node backend beside
# a frontend with no stack configured is the same refusal as an empty cwd, not a
# probed verdict, and a .NET project does not switch an unset stack to extensions.
node_react="$(make_tree 'package.json:{"dependencies":{"express":"^4","react":"^18"}}')"
assert_block "markers do not stand in for an unset stack" \
  "$HOOK" "$(payload_file tank src/app.ts)" "Run /crew:init" "$node_react"
mixed="$(make_tree 'Api.csproj:<Project />' 'package.json:{"dependencies":{"express":"^4"}}')"
assert_block "a .csproj does not switch an unset stack to extensions" \
  "$HOOK" "$(payload_file tank Api/Foo.cs)" "Run /crew:init" "$mixed"

finish
