#!/usr/bin/env bash
# Per-agent file-write lanes for PreToolUse(Edit|Write), routed on the payload's
# `agent_type` since plugin agents cannot carry their own hooks. Lane paths win
# when configured, else extension globs; a same-language pair with no paths, or
# an unset backend stack, fails closed. The guard reads slots and detects nothing
# (AGENTS.md, "Init is the only detector").

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
# One jq pass; the path is only computed for a lane agent (see guard_jq2).
# shellcheck disable=SC2016  # $at is a jq variable, not a shell one
if ! guard_jq2 \
  '((.agent_type // "") | if startswith("crew:") then .[5:] else "" end) as $at | (if (["unit-tests","e2e","backend","frontend","lead"] | index($at)) then ((.tool_input.file_path // .tool_input.path) // "") else "" end)' \
  '.agent_type // ""'; then
  echo "Blocked: lane-guard could not parse the hook payload." >&2
  exit 2
fi
guard_agent_type
path="$guard_untrusted"

# The main session and `generalist` (the express lane) have no lane and bail here.
# crew-roster: lane-guarded -- validator §9 keeps the arm below in lockstep with
# the agents' frontmatter `lane-guarded`. Load-bearing shape: this marker, then
# the `case` header, then the `a|b|c)` arm on the very next line.
case "$agent_type" in
  unit-tests|e2e|backend|frontend|lead) ;;
  *) exit 0 ;;
esac
[ -z "$path" ] && exit 0

# A `..` segment dodges a prefix either way; this guard resolves nothing, so it
# refuses the segment for every lane agent.
case "/$path/" in
  */../*)
    echo "Blocked: $path has a '..' segment — name the file by its plain path." >&2
    exit 2 ;;
esac

# Loaded once in the parent shell: config_slot runs in `$(...)`.
guard_config_load

# Comma-separated paths -> "<path>/**" globs. IFS, not command substitution,
# which would glob-expand a value against the filesystem.
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

# agent_type -> mode + glob patterns; exempt bypasses a deny, confine and exclude
# narrow an allow.
exempt=""
confine=""
exclude=""
case "$agent_type" in
  # The union of every stack's test convention, minus the e2e directories, which
  # are e2e's (a Playwright `e2e/foo.spec.ts` would otherwise be unit-tests's too).
  unit-tests) mode="--allow"
          patterns='**/*Tests/** **/*.Tests.* tests/** **/__tests__/** **/*.test.* **/*.spec.*'
          patterns+=' **/test*.py **/*_test.py **/conftest.py'    # pytest + unittest discover
          patterns+=' **/*_test.go **/testdata/**'                 # go test + its fixtures
          patterns+=' **/*.bats **/*.test.sh'                      # bats + plain-bash harness
          # Every Surefire/Failsafe name convention, not just src/test: a custom
          # Gradle source set puts these classes elsewhere.
          patterns+=' **/src/test/** **/*Test.java **/Test*.java **/*Tests.java'
          patterns+=' **/*TestCase.java **/*IT.java **/IT*.java **/*ITCase.java'
          exclude='e2e/** cypress/** playwright/** tests/e2e/**' ;;
  e2e)
    # The configured e2e tool's locations. A bare tests/** also matches backend
    # tests, so Playwright gets it only when a frontend lane path confines it.
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
    [ -n "$frontend_lane" ] && confine="$(lane_globs "$frontend_lane")"
    ;;
  backend|frontend)
    backend_lane="$(config_slot backendLanePaths)"
    frontend_lane="$(config_slot frontendLanePaths)"
    backend_stack="$(config_slot backendStack)"
    frontend_stack="$(config_slot frontendStack)"
    if [ -z "$backend_stack" ]; then
      echo "Blocked: Backend stack is not configured, so ${agent_type} has no lane. Run /crew:init before delegating." >&2
      exit 2
    elif [ -n "$backend_lane" ] && [ -n "$frontend_lane" ]; then
      # Route handlers live in the frontend tree but are backend's by concern.
      route_handlers='app/**/route.ts app/**/route.js pages/api/**'
      mode="--deny"
      if [ "$agent_type" = "backend" ]; then
        patterns="$(lane_globs "$frontend_lane")"
        exempt="$route_handlers"
      else
        patterns="$(lane_globs "$backend_lane") $route_handlers"
      fi
    elif [ -n "$backend_lane" ] || [ -n "$frontend_lane" ]; then
      echo "Blocked: only one of Backend lane path(s) / Frontend lane path(s) is configured. Set both in .claude/crew.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ] && [ -n "$frontend_stack" ]; then
      echo "Blocked: backend stack is node — backend and frontend can both touch .ts/.js files, so extension-based lanes can't tell them apart. Set Backend lane path(s) / Frontend lane path(s) in .claude/crew.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ]; then
      # Backend-only Node: backend owns the tree; frontend has no lane to scope to.
      [ "$agent_type" = "backend" ] && exit 0
      echo "Blocked: backend stack is node with no frontend configured — frontend has no frontend lane here. Set a Frontend stack / Frontend lane path(s) in .claude/crew.md (see /crew:init) before delegating frontend work." >&2
      exit 2
    else
      # Extension regime. .cshtml is shared by concern, so neither agent is denied
      # it; the prompts hold that split. frontend's list is the union of every
      # backend's files, manifests included, not the configured stack's.
      mode="--deny"
      if [ "$agent_type" = "backend" ]; then
        patterns='*.ts *.tsx *.jsx *.js *.mjs *.scss *.css *.html'
      else
        patterns='*.cs *.csproj'                                     # dotnet
        patterns+=' *.py *.pyi pyproject.toml requirements*.txt setup.py setup.cfg'
        patterns+=' tox.ini Pipfile Pipfile.lock poetry.lock uv.lock pdm.lock'
        patterns+=' mypy.ini .mypy.ini pyrightconfig.json pytest.ini ruff.toml .ruff.toml .flake8'  # python
        patterns+=' *.go go.mod go.sum go.work go.work.sum .golangci.yml .golangci.yaml'
        patterns+=' **/testdata/**'                                              # go
        patterns+=' *.rs Cargo.toml Cargo.lock rustfmt.toml .rustfmt.toml clippy.toml'   # rust
        patterns+=' *.java pom.xml build.gradle build.gradle.kts'
        patterns+=' settings.gradle settings.gradle.kts gradle.properties'
        patterns+=' gradle/libs.versions.toml gradle/wrapper/gradle-wrapper.properties'
        # Only the config under src/main/resources: templates/ and static/ are the view.
        patterns+=' **/src/main/resources/application*.properties'
        patterns+=' **/src/main/resources/application*.yml **/src/main/resources/application*.yaml'
        patterns+=' **/src/main/resources/bootstrap*.yml **/src/main/resources/bootstrap*.yaml'
        patterns+=' **/src/test/**'                                              # java
        patterns+=' *.sh *.bash *.bats .shellcheckrc'                             # shell
      fi
    fi
    ;;
  # lead writes plans, ledgers, config, memory and scratch: a filename shape
  # at any depth, never a directory (AGENTS.md, "Why `lead` is lane-guarded").
  lead) mode="--allow"
            patterns='plan-*.md */plan-*.md debt-*.md */debt-*.md crew.md */crew.md'
            patterns+=' */agent-memory-local/*.md */agent-memory/*.md'   # Markdown only
            patterns+=' /tmp/** /private/tmp/** /var/folders/** /private/var/folders/**' ;;
  *) exit 0 ;;  # read-only agents never reach this hook
esac

# True if $path matches any glob in $1. set -f keeps the patterns literal; the
# */ and ./ prefixes let one pattern match absolute and repo-relative paths.
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

if [ "$mode" = "--allow" ] && [ -n "$exclude" ] && matches "$exclude"; then
  echo "Blocked: $path is in an e2e lane (e2e's), not ${agent_type}'s." >&2
  exit 2
fi

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
