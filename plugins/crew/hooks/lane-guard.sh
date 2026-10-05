#!/usr/bin/env bash
# Per-agent file-write lane enforcement for PreToolUse(Edit|Write). Routes on the
# `agent_type` the harness adds to the payload; plugin agents can't carry their
# own hooks, so the lanes are centralized here.
#
# Directory lanes (the crew-configuration path slots) win when set, else extension globs. A
# same-language pair (node backend + JS frontend) with no lane paths fails CLOSED
# -- extensions can't separate tank's files from trinity's. The guard detects
# nothing: an unset backend stack is a refusal naming /crew:init, the only
# detector (AGENTS.md, "Init is the only detector"). A backend-only Node repo has
# no such conflict, so enforcement is skipped.

# Fail closed: a guard that can't read its input must block, not allow.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
if ! . "$_lib" 2>/dev/null; then
  echo "Blocked: lane-guard could not load its guard library ($_lib)." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: lane-guard needs jq to enforce write lanes." >&2
  exit 2
fi

guard_read_payload
# One jq pass for both fields; the path is the untrusted one, so the split anchors
# on agent_type (see guard_jq2). jq only computes the path for a lane agent, so a
# non-lane session never pays even for the field lookup.
# shellcheck disable=SC2016  # $at is a jq variable, not a shell one
if ! guard_jq2 \
  '((.agent_type // "") | sub("^crew:"; "")) as $at | (if (["oracle","dozer","tank","trinity","morpheus"] | index($at)) then ((.tool_input.file_path // .tool_input.path) // "") else "" end)' \
  '.agent_type // ""'; then
  echo "Blocked: lane-guard could not parse the hook payload." >&2
  exit 2
fi
guard_agent_type
path="$guard_untrusted"

# Bail before any further parsing for the common case: the main session, or any
# agent with no lane. `neo` is the express-lane generalist, so it has no lane
# restriction by design and bails here. Kept in sync with the lane dispatch below.
# crew-roster: lane-guarded -- validator §9 keeps the arm below in lockstep with
# the agents' frontmatter `lane-guarded`. Load-bearing shape: this marker, then
# the `case` header, then the `a|b|c)` arm on the very next line.
case "$agent_type" in
  oracle|dozer|tank|trinity|morpheus) ;;
  *) exit 0 ;;
esac
[ -z "$path" ] && exit 0

# A `..` segment lets an allowed prefix name a file outside it (`.claude/../src/app.ts`)
# and a denied prefix be dodged the same way. This guard matches strings and resolves
# nothing, and no agent has a reason to edit through one, so it is refused for every
# lane agent instead.
case "/$path/" in
  */../*)
    echo "Blocked: $path has a '..' segment — name the file by its plain path." >&2
    exit 2 ;;
esac

# Crew configuration: the frontmatter is slurped once here in the parent shell
# (guard_config_load) and matched in-process -- a lane dispatch reads up to four
# slots, and shelling out per slot cost eight processes before the agent's edit
# could land.
guard_config_load

# Comma-separated path config -> space-separated "<path>/**" globs. Split on
# commas via IFS rather than command substitution, which would word-split and
# glob-expand a value containing * ? [ against the filesystem.
lane_globs() {
  local IFS=','
  set -f
  for p in $1; do
    p="${p#"${p%%[![:space:]]*}"}"   # trim leading whitespace
    p="${p%"${p##*[![:space:]]}"}"   # trim trailing whitespace
    [ -z "$p" ] && continue
    case "$p" in */) printf '%s** ' "$p" ;; *) printf '%s/** ' "$p" ;; esac
  done
  set +f
}

# agent_type -> mode + space-separated glob patterns (+ optional exempt patterns
# that bypass a deny before it's evaluated, confine patterns an --allow path must
# also be inside, and exclude patterns that deny an --allow path even if it matches).
exempt=""
confine=""
exclude=""
case "$agent_type" in
  # `.spec.*` is kept (Vitest/Jest/Angular unit tests use it), but oracle is
  # excluded from the e2e-tool directories, which are dozer's — otherwise a
  # Playwright `e2e/foo.spec.ts` would fall in oracle's lane too.
  # The union of every stack's test convention: the stack isn't resolved here, so
  # a test file in *any* of them is oracle's.
  oracle) mode="--allow"
          patterns='**/*Tests/** **/*.Tests.* tests/** **/__tests__/** **/*.test.* **/*.spec.*'
          patterns+=' **/test*.py **/*_test.py **/conftest.py'    # pytest + unittest discover
          patterns+=' **/*_test.go **/testdata/**'                 # go test + its fixtures
          patterns+=' **/*.bats **/*.test.sh'                      # bats + plain-bash harness
          # Every Surefire/Failsafe name convention, not just src/test: a custom
          # Gradle source set puts these classes elsewhere.
          patterns+=' **/src/test/** **/*Test.java **/Test*.java **/*Tests.java'
          patterns+=' **/*TestCase.java **/*IT.java **/IT*.java **/*ITCase.java'
          exclude='e2e/** cypress/** playwright/** tests/e2e/**' ;;
  dozer)
    # Scope to the resolved e2e tool's conventional locations rather than a blanket
    # tests/** that would reach backend/unit tests. Playwright's default testDir is
    # tests/ or e2e/, but a bare tests/** also matches nested backend test dirs and
    # overlaps oracle, so it is only widened to tests/** when a Frontend lane path
    # is configured (the confine below then keeps it in-lane). The broad fallback
    # applies only when the tool is unset/unknown.
    mode="--allow"
    frontend_lane="$(config_slot frontendLanePaths)"
    case "$(config_slot frontendE2eTool)" in
      cypress)    patterns='cypress/** **/*.cy.*' ;;
      playwright)
        if [ -n "$frontend_lane" ]; then
          patterns='e2e/** playwright/** tests/**'
        else
          patterns='e2e/** playwright/** tests/e2e/**'
        fi
        ;;
      *)          patterns='cypress/** e2e/** tests/** playwright/** **/*.cy.*' ;;
    esac
    # In a same-language monorepo a bare tests/** can match backend tests (e.g.
    # apps/api/tests/**), so a configured Frontend lane path also confines dozer:
    # an e2e-shaped path outside that lane is still denied.
    [ -n "$frontend_lane" ] && confine="$(lane_globs "$frontend_lane")"
    ;;
  tank|trinity)
    backend_lane="$(config_slot backendLanePaths)"
    frontend_lane="$(config_slot frontendLanePaths)"
    backend_stack="$(config_slot backendStack)"
    frontend_stack="$(config_slot frontendStack)"
    if [ -n "$backend_lane" ] && [ -n "$frontend_lane" ]; then
      # Route handlers live in the frontend tree but are tank's by concern
      # (single-owner, unlike Razor's markup/logic split) — exempt tank, deny trinity.
      route_handlers='app/**/route.ts app/**/route.js pages/api/**'
      mode="--deny"
      if [ "$agent_type" = "tank" ]; then
        patterns="$(lane_globs "$frontend_lane")"
        exempt="$route_handlers"
      else
        patterns="$(lane_globs "$backend_lane") $route_handlers"
      fi
    elif [ -n "$backend_lane" ] || [ -n "$frontend_lane" ]; then
      # One lane path set but not both. Fail closed rather than falling back to
      # the extension regime, which can't separate tank from trinity in
      # same-language stacks.
      echo "Blocked: only one of Backend lane path(s) / Frontend lane path(s) is configured. Set both in .claude/crew.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ -z "$backend_stack" ]; then
      # Which regime applies is a property of the project, pinned once by
      # /crew:init; the guard does not probe the tree for it.
      echo "Blocked: Backend stack is not configured, so ${agent_type} has no lane. Run /crew:init before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ] && [ -n "$frontend_stack" ]; then
      echo "Blocked: backend stack is node — tank and trinity can both touch .ts/.js files, so extension-based lanes can't tell them apart. Set Backend lane path(s) / Frontend lane path(s) in .claude/crew.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ]; then
      # Backend-only Node repo (no Frontend stack configured). tank owns the whole
      # Node codebase, so it writes freely; trinity has no frontend lane to scope
      # to here, so it fails closed rather than getting unrestricted access.
      [ "$agent_type" = "tank" ] && exit 0
      echo "Blocked: backend stack is node with no frontend configured — trinity has no frontend lane here. Set a Frontend stack / Frontend lane path(s) in .claude/crew.md (see /crew:init) before delegating frontend work." >&2
      exit 2
    else
      # Extension-based regime (default). .cshtml is intentionally NOT denied to
      # either agent: Razor is shared by concern (trinity = markup/DOM, tank =
      # C#/server logic), and that split is enforced by the agent prompts, since
      # file globs can't see inside a file.
      # trinity's deny list is the union of every backend's extensions, not the
      # resolved stack's: none of them is a client-facing file. These stacks reach
      # here rather than node's branch above because their extensions are disjoint
      # from the frontend's.
      mode="--deny"
      if [ "$agent_type" = "tank" ]; then
        patterns='*.ts *.tsx *.jsx *.js *.mjs *.scss *.css *.html'
      else
        patterns='*.cs *.csproj'                                     # dotnet
        # Manifests and build config count: they are backend-owned, and leaving
        # them out lets the lane fail open on exactly the dependency files a
        # frontend agent has no business editing.
        patterns+=' *.py *.pyi pyproject.toml requirements*.txt setup.py setup.cfg'
        patterns+=' tox.ini Pipfile Pipfile.lock poetry.lock uv.lock pdm.lock'
        patterns+=' mypy.ini .mypy.ini pyrightconfig.json pytest.ini ruff.toml .ruff.toml .flake8'  # python
        patterns+=' *.go go.mod go.sum go.work go.work.sum .golangci.yml .golangci.yaml'
        patterns+=' **/testdata/**'                                              # go
        patterns+=' *.rs Cargo.toml Cargo.lock rustfmt.toml .rustfmt.toml clippy.toml'   # rust
        patterns+=' *.java pom.xml build.gradle build.gradle.kts'
        patterns+=' settings.gradle settings.gradle.kts gradle.properties'
        patterns+=' gradle/libs.versions.toml gradle/wrapper/gradle-wrapper.properties'
        # Backend config under src/main/resources. NOT the whole tree: templates/
        # and static/ under it are the view layer, so they stay trinity's the way
        # .cshtml does.
        patterns+=' **/src/main/resources/application*.properties'
        patterns+=' **/src/main/resources/application*.yml **/src/main/resources/application*.yaml'
        patterns+=' **/src/main/resources/bootstrap*.yml **/src/main/resources/bootstrap*.yaml'
        patterns+=' **/src/test/**'                                              # java
        patterns+=' *.sh *.bash *.bats .shellcheckrc'                             # shell
      fi
    fi
    ;;
  # morpheus writes Markdown plans and ledgers, crew config, its agent memory and
  # scratch, never production code. The lane is a filename shape at any depth, not
  # a directory: production code is never named plan-*.md, so there is no root to
  # anchor and no plan-directory slot to read. See AGENTS.md, "Prompt design
  # rationale" -> "crew:debt (the debt lane)".
  morpheus) mode="--allow"
            patterns='plan-*.md */plan-*.md debt-*.md */debt-*.md crew.md */crew.md'
            # `memory: local` writes Markdown under .claude/agent-memory-local/ (AGENTS.md,
            # "Conventions"). Markdown only, so a lookalike directory cannot carry source.
            patterns+=' */agent-memory-local/*.md */agent-memory/*.md'
            patterns+=' /tmp/** /private/tmp/** /var/folders/** /private/var/folders/**' ;;
  # seraph, sentinel and keymaker are read-only with no edit/write tools, so they
  # never reach this Edit|Write hook — no lane entry needed.
  *) exit 0 ;;  # main session or any agent without a lane: no restriction
esac

# True if $path matches any glob in $1 (space-separated). set -f keeps patterns
# literal for [[ ]] instead of expanding them against the filesystem. The */
# prefix lets repo-relative patterns match an absolute file_path, and the ./
# prefix lets **/-anchored patterns match a repo-relative one (** needs a leading
# component to consume); in [[ ]] a single * already spans '/'.
matches() {
  set -f
  for g in $1; do
    # shellcheck disable=SC2053
    if [[ "$path" == $g || "$path" == */$g || "./$path" == $g ]]; then
      set +f
      return 0
    fi
  done
  set +f
  return 1
}

if [ -n "$exempt" ] && matches "$exempt"; then
  exit 0
fi

if matches "$patterns"; then match=1; else match=0; fi

# An --allow agent with an exclude set is denied a path that matches it even when
# it also matches the allow patterns: it keeps oracle's test globs out of the
# e2e-tool directories, which are dozer's lane.
if [ "$mode" = "--allow" ] && [ -n "$exclude" ] && matches "$exclude"; then
  echo "Blocked: $path is in an e2e lane (dozer's), not ${agent_type}'s." >&2
  exit 2
fi

# An --allow agent with a confine set must ALSO be inside the confine globs, which
# keeps dozer's e2e patterns within the configured frontend lane: a tests/** match
# in a backend lane is still denied.
if [ "$mode" = "--allow" ] && [ -n "$confine" ] && ! matches "$confine"; then
  echo "Blocked: $path is outside ${agent_type}'s frontend lane." >&2
  exit 2
fi

if [ "$mode" = "--deny" ] && [ "$match" = 1 ]; then
  echo "Blocked: $path is out of ${agent_type}'s lane." >&2
  exit 2
fi
if [ "$mode" = "--allow" ] && [ "$match" = 0 ]; then
  echo "Blocked: $path is outside ${agent_type}'s allowed paths." >&2
  exit 2
fi
exit 0
