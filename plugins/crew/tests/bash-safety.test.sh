#!/usr/bin/env bash
# Behavioral tests for hooks/bash-safety.sh.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="bash-safety.sh"

# --- Workers run no git but a plain git mv -------------------------------------
nogit="runs no git but a plain"
for agent in backend frontend unit-tests e2e generalist; do
  assert_block "worker $agent blocked from git" "$HOOK" "$(payload_bash 'git status' "$agent")" "$nogit"
done
assert_allow "git in a no-agent session" "$HOOK" "$(payload_bash 'git status')"
# An installed plugin's worker calls tools as `crew:backend`.
assert_block "crew:backend blocked from git" "$HOOK" "$(payload_bash 'git status' crew:backend)" "$nogit"
assert_allow "other:backend is not this crew's worker" "$HOOK" "$(payload_bash 'git status' other:backend)"
assert_block "smuggled env git push (backend)" "$HOOK" "$(payload_bash 'env git push' backend)" "$nogit"
assert_block "smuggled FOO=1 git (backend)" "$HOOK" "$(payload_bash 'FOO=1 git status' backend)" "$nogit"

# --- Protected-branch commit backstop -----------------------------------------
main_repo="$(make_git_branch main)"
feat_repo="$(make_git_branch feature/x)"
assert_block "lead git commit on main" "$HOOK" "$(payload_bash 'git commit -m x' lead)" "protected branch" "$main_repo"
assert_allow "lead git commit on feature branch" "$HOOK" "$(payload_bash 'git commit -m x' lead)" "$feat_repo"
assert_allow "no-agent session may commit on main" "$HOOK" "$(payload_bash 'git commit -m x')" "$main_repo"
# The branch is read where the commit runs (#224): the payload's cwd, or a literal
# `git -C <dir>` / `cd <dir> &&` over the whole command. Any other shape stays on
# cwd. The hook itself runs in $main_repo throughout.
at() { jq -c --arg d "$2" '. + {cwd: $d}' <<<"$1"; }
assert_allow "cwd on a feature worktree"  "$HOOK" "$(at "$(payload_bash 'git commit -m x' lead)" "$feat_repo")" "$main_repo"
assert_block "cwd on main"                "$HOOK" "$(at "$(payload_bash 'git commit -m x' lead)" "$main_repo")" "protected branch" "$feat_repo"
assert_allow "git -C a feature worktree"  "$HOOK" "$(at "$(payload_bash "git -C $feat_repo commit -m x" lead)" "$main_repo")" "$main_repo"
assert_allow "cd a feature worktree &&"   "$HOOK" "$(at "$(payload_bash "cd $feat_repo && git commit -m 'fix it'" lead)" "$main_repo")" "$main_repo"
assert_block "git -C main from a worktree" "$HOOK" "$(at "$(payload_bash "git -C $main_repo commit -m x" lead)" "$feat_repo")" "protected branch" "$feat_repo"
assert_block "a second clause stays on cwd" "$HOOK" "$(at "$(payload_bash "cd $feat_repo && git commit -m x; git commit -m y" lead)" "$main_repo")" "protected branch" "$main_repo"
# Any other shape also checks the hook's own directory, so it is never weaker
# than before: here cwd is a feature branch and only the hook's directory is main.
# shellcheck disable=SC2016  # $WT is the literal text under test
assert_block "an expanded dir checks the hook's dir" "$HOOK" "$(at "$(payload_bash 'git -C "$WT" commit -m x' lead)" "$feat_repo")" "protected branch" "$main_repo"
assert_block "a GIT_DIR prefix checks the hook's dir" "$HOOK" "$(at "$(payload_bash "GIT_DIR=$main_repo/.git git commit -m x" lead)" "$feat_repo")" "protected branch" "$main_repo"
assert_block "cd - is not a literal dir"  "$HOOK" "$(at "$(payload_bash 'cd - && git commit -m x' lead)" "$feat_repo")" "protected branch" "$main_repo"

# --- Destructive commands ------------------------------------------------------
assert_block "rm -rf /"        "$HOOK" "$(payload_bash 'rm -rf /' backend)"        "unsafe command"
assert_block "rm -fr ~"        "$HOOK" "$(payload_bash 'rm -fr ~' backend)"        "unsafe command"
assert_block "rm -rf *"        "$HOOK" "$(payload_bash 'rm -rf *' backend)"        "unsafe command"
assert_block "rm -r -f /"      "$HOOK" "$(payload_bash 'rm -r -f /' backend)"      "unsafe command"
assert_allow "rm -rf ./build (scoped)" "$HOOK" "$(payload_bash 'rm -rf ./build' backend)"
# Every absolute or home target is refused with -rf, root-wide spellings and
# build dirs alike (#264 tried narrower and leaked). Out-of-tree cleanup uses
# `rm -r` without -f, which the rule never matches.
# shellcheck disable=SC2088  # the `~` is command text for the hook, not to expand here
for t in '/*' '/*/' '//' '/.' '/tmp/../*' '~/' '~/*/' '**' '/d/repos/build-scratch/app'; do
  assert_block "rm -rf $t" "$HOOK" "$(payload_bash "rm -rf $t" backend)" "unsafe command"
done
assert_allow "rm -r of an absolute build dir" "$HOOK" "$(payload_bash 'rm -r /d/repos/build-scratch/app/20233' backend)"
assert_block "rm -rf / then more" "$HOOK" "$(payload_bash 'rm -rf / && ls' backend)" "unsafe command"
assert_block "rm -rf a then /"  "$HOOK" "$(payload_bash 'rm -rf build /' backend)"  "unsafe command"
assert_block "rm -rf / glued to a redirect"  "$HOOK" "$(payload_bash 'rm -rf --no-preserve-root />/tmp/log' backend)" "unsafe command"

# --- Force-push ----------------------------------------------------------------
# Force-push detection is agentless here (uses a non-worker agent so the generic
# worker-git block doesn't mask it); the destructive regex fires regardless.
assert_block "git push --force"   "$HOOK" "$(payload_bash 'git push --force' lead)"   "unsafe command"
assert_block "git push -f"        "$HOOK" "$(payload_bash 'git push -f' lead)"         "unsafe command"
assert_allow "git push --force-with-lease" "$HOOK" "$(payload_bash 'git push --force-with-lease' lead)"

# --- Redirects / .git writes ---------------------------------------------------
assert_block "redirect into .env"        "$HOOK" "$(payload_bash 'echo secret > .env' backend)"       "unsafe command"
assert_block "redirect into .git/config" "$HOOK" "$(payload_bash 'echo x > .git/config' backend)"     "unsafe command"
assert_block "noclobber redirect into .env" "$HOOK" "$(payload_bash 'echo secret >| .env' backend)"   "unsafe command"
assert_block "rm inside .git/"           "$HOOK" "$(payload_bash 'rm .git/index' backend)"             "unsafe command"

# --- Watch/dev/serve commands (agent sessions only) ---------------------------
for cmd in 'dotnet watch' 'npm run dev' 'pnpm dev' 'vite' 'next dev' 'ng serve' 'nodemon' 'webpack serve'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" backend)" "never terminate"
done
assert_block "bare --watch flag" "$HOOK" "$(payload_bash 'jest --watch' backend)" "never terminate"
assert_allow "vite build (not a dev server)"  "$HOOK" "$(payload_bash 'vite build' backend)"
assert_allow "--watch=false (disable spelling)" "$HOOK" "$(payload_bash 'jest --watch=false' backend)"

# The same rule in the non-web stacks.
for cmd in 'uvicorn app:app --reload' 'uvicorn app:app' 'hypercorn app:app' 'gunicorn wsgi:app' \
           'python manage.py runserver' 'flask run' 'flask --app app run' 'ptw' 'watchmedo auto-restart' \
           'poetry run uvicorn app:app' 'uv run flask run' 'pipenv run uvicorn app:app' \
           'fastapi dev app.py' 'fastapi run' \
           'django-admin runserver' 'python -m django runserver' \
           'python services/api/manage.py runserver' \
           'uv run python -m uvicorn app:app' 'poetry run python -m flask run' \
           '.venv/bin/python -m uvicorn app:app' 'python3.12 -m uvicorn app:app' \
           '.venv/bin/uvicorn app:app' \
           'uv run --project service uvicorn app:app' 'pdm run --site-packages flask run' \
           'poetry -C service run uvicorn app:app' 'uv --directory service run uvicorn app:app' \
           'watch shellcheck .' '/usr/bin/watch shellcheck .' 'watchexec -- shellcheck .' 'entr make' \
           'air' 'reflex' 'cargo watch' 'cargo watch -x test' 'cargo +nightly watch -x test' \
           'trunk serve' 'python -m http.server' 'python3 -m http.server 8000' \
           './mvnw spring-boot:run' 'mvn quarkus:dev' './gradlew bootRun' './gradlew build --continuous' \
           'service/mvnw spring-boot:run' './service/gradlew bootRun'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" backend)" "never terminate"
done
# One-shot commands in the same ecosystems stay allowed: refusing one of these
# would break the gate it belongs to.
for cmd in 'pytest -q' 'mypy .' 'ruff check .' 'python -m pytest tests/' \
           'uv run pytest' 'poetry run python -m pytest tests/' 'python -m build' 'pipenv run pytest' \
           'django-admin startproject x' 'python -m django --version' \
           'python services/api/manage.py migrate' \
           '.venv/bin/python -m pytest' 'python3.12 -m build' \
           'uv run --project service pytest' 'pdm run --site-packages pytest' 'shellcheck hooks/a.sh' \
           'poetry -C service run pytest' 'uv --directory service run pytest' \
           'go build ./...' 'go test ./...' 'go run ./cmd/tool' \
           'cargo test' 'cargo build --all-targets' 'cargo clippy -- -D warnings' 'cargo +nightly test' \
           './mvnw -B verify' './gradlew test' './gradlew check -x test' \
           'service/mvnw -B verify' './service/gradlew test'; do
  assert_allow "one-shot: $cmd" "$HOOK" "$(payload_bash "$cmd" backend)"
done
assert_allow "npm run build"                  "$HOOK" "$(payload_bash 'npm run build' backend)"
assert_allow "npm run dev in a no-agent session" "$HOOK" "$(payload_bash 'npm run dev')"

# --- Raw / streaming reads -----------------------------------------------------
# A habit redirect, not a boundary: the rule catches the spelling a session
# reaches for and names the tool instead. `grep . f` dumps the same file and is
# deliberately allowed, so the cases below pin the habit and the escapes, not
# redirect spellings -- see AGENTS.md, "The Bash guards are floors, not sandboxes".
assert_block "cat a file"     "$HOOK" "$(payload_bash 'cat foo.txt' backend)"      "unbounded cat"
assert_block "cat then another command" "$HOOK" "$(payload_bash 'cat foo.txt; ls' backend)" "unbounded cat"
assert_block "less a file"    "$HOOK" "$(payload_bash 'less foo.txt' backend)"     "interactive raw reads"
assert_block "tail -f a log"  "$HOOK" "$(payload_bash 'tail -f app.log' backend)"  "streaming raw output"
# Pagers and `tail -f` hang any session, so they are refused in every one. The
# `cat` redirect is for agents only: the operator's own `cat` bypasses nothing.
assert_allow "bare cat with no agent_type" "$HOOK" "$(payload_bash 'cat foo.txt')"
assert_block "less with no agent_type"     "$HOOK" "$(payload_bash 'less foo.txt')"    "interactive raw reads"
assert_block "tail -f with no agent_type"  "$HOOK" "$(payload_bash 'tail -f app.log')" "streaming raw output"
assert_block "lead cat"                "$HOOK" "$(payload_bash 'cat foo.txt' lead)" "unbounded cat"
# A wrapper the command-position policy already knows must not walk a read past
# the guard, on any of the three rules.
assert_block "env cat"       "$HOOK" "$(payload_bash 'env cat foo.txt' backend)"     "unbounded cat"
assert_block "command cat"   "$HOOK" "$(payload_bash 'command cat foo.txt' backend)" "unbounded cat"
assert_block "FOO=1 cat"     "$HOOK" "$(payload_bash 'FOO=1 cat foo.txt' backend)"   "unbounded cat"
assert_block "env less"      "$HOOK" "$(payload_bash 'env less foo.txt' backend)"    "interactive raw reads"
assert_block "env tail -f"   "$HOOK" "$(payload_bash 'env tail -f app.log' backend)" "streaming raw output"
# Filtering is the documented way out, and any redirect ends the match too.
assert_allow "cat piped into grep"        "$HOOK" "$(payload_bash 'cat foo.txt | grep x' backend)"
assert_allow "cat redirected into a file" "$HOOK" "$(payload_bash 'cat foo.txt > out.txt')"
assert_allow "bounded reads stay available" "$HOOK" "$(payload_bash 'head -40 foo.txt' backend)"
# The refusals are a user-facing contract: they name the tool to use and say why
# the shell read is refused. Asserted apart from the category substrings above,
# which would still pass if the guidance were dropped.
assert_block "cat refusal names the Read tool"   "$HOOK" "$(payload_bash 'cat foo.txt' backend)"  "Use the Read tool"
assert_block "cat refusal gives the reason"      "$HOOK" "$(payload_bash 'cat foo.txt' backend)"  "reaches no Read hook"
assert_block "pager refusal names the Read tool" "$HOOK" "$(payload_bash 'less foo.txt' backend)" "Use the Read tool"
assert_block "pager refusal gives the reason"    "$HOOK" "$(payload_bash 'less foo.txt' backend)" "reaches no Read hook"
# Nothing replaces a `tail -f`, so the stream refusal points at capture/filter --
# but it carries the same reason, and the category substring alone was in the old
# message too, so a revert to that wording would have passed.
assert_block "stream refusal gives the reason"   "$HOOK" "$(payload_bash 'tail -f app.log' backend)" "reaches no Read hook"

# --- File writes through Bash (agent sessions only) ---------------------------
# lane-guard and format.sh are wired to Edit|Write, so a Bash write would land
# outside both. Blocking it here keeps one enforcement point instead of
# reimplementing lane resolution on the Bash path (#192).
gap="reaches no Edit|Write hook"
assert_block "sed -i"             "$HOOK" "$(payload_bash "sed -i 's/a/b/' src/Foo.cs" backend)"   "$gap"
assert_block "sed -i.bak"         "$HOOK" "$(payload_bash 'sed -i.bak s/a/b/ src/Foo.cs' backend)" "$gap"
assert_block "perl -pi -e"        "$HOOK" "$(payload_bash "perl -pi -e 's/a/b/' src/Foo.cs" backend)" "$gap"
assert_block "sed -i under -exec" "$HOOK" "$(payload_bash "find . -name '*.cs' -exec sed -i s/a/b/ {} +" backend)" "$gap"
assert_block "redirect into a file"   "$HOOK" "$(payload_bash 'echo x > src/Foo.cs' backend)"  "$gap"
assert_block "glued redirect"         "$HOOK" "$(payload_bash 'echo x>src/Foo.cs' backend)"    "$gap"
assert_block "append redirect"        "$HOOK" "$(payload_bash 'printf x >> README.md' backend)" "$gap"
assert_block "quoted redirect target" "$HOOK" "$(payload_bash 'echo x > "src/Foo.cs"' backend)" "quoted path"
# An absolute path outside the project is not guarded by the lane or format
# hooks, so a redirect there (an out-of-tree build log, #240) is allowed. Inside
# the project, unset project dir, `..`, and /dev stay refused.
export CLAUDE_PROJECT_DIR=/home/dev/proj
assert_allow "redirect to an out-of-tree build root" "$HOOK" "$(payload_bash 'dotnet build > /d/repos/build-scratch/app/build.log 2>&1' backend)"
# Off Windows, `D:/x` and `\x` are relative names in the checkout.
assert_block "drive-looking path off Windows"        "$HOOK" "$(payload_bash 'dotnet build > D:/build/log.txt' backend)" "$gap"
assert_block "backslash path off Windows"            "$HOOK" "$(payload_bash 'echo x > \tmp\x' backend)" "$gap"
assert_block "absolute redirect into the project"    "$HOOK" "$(payload_bash 'echo x > /home/dev/proj/src/Foo.cs' backend)" "$gap"
assert_block "absolute redirect, other case"         "$HOOK" "$(payload_bash 'echo x > /HOME/dev/Proj/src/Foo.cs' backend)" "$gap"
assert_block "absolute redirect climbing back in"    "$HOOK" "$(payload_bash 'echo x > /home/dev/other/../proj/a' backend)" "$gap"
# The allow-list fails closed on anything bash could expand or re-spell.
# shellcheck disable=SC2016  # the `$P` and backticks are command text, not to expand here
for t in '/home/dev/$P/a' '/home/dev/./proj/a' '/home/dev//proj/a' '/home/dev/pro*/a' '/home/`echo dev`/a' '/build/.hidden/log'; do
  assert_block "redirect to $t" "$HOOK" "$(payload_bash "echo x > $t" backend)" "$gap"
done
assert_block "redirect to /dev/tcp"                  "$HOOK" "$(payload_bash 'echo x > /dev/tcp/h/80' backend)" "$gap"
CLAUDE_PROJECT_DIR='C:\work\proj'
export CREW_OSTYPE=msys
assert_block "Git Bash path into a Windows project"  "$HOOK" "$(payload_bash 'echo x > /c/work/proj/a.cs' backend)" "$gap"
assert_block "drive path into a Windows project"     "$HOOK" "$(payload_bash 'echo x > C:/work/proj/a.cs' backend)" "$gap"
assert_allow "Git Bash path outside a Windows project" "$HOOK" "$(payload_bash 'echo x > /c/build/a.log' backend)"
assert_allow "drive path outside a Windows project"  "$HOOK" "$(payload_bash 'dotnet build > D:/build/log.txt' backend)"
assert_block "drive-relative path on Windows"        "$HOOK" "$(payload_bash 'echo x > D:src/Foo.cs' backend)" "$gap"
unset CLAUDE_PROJECT_DIR CREW_OSTYPE
# A quoted target is masked before the exempt check, so it stays refused.
export CLAUDE_PROJECT_DIR=/home/dev/proj
assert_block "quoted out-of-tree target"             "$HOOK" "$(payload_bash 'dotnet build > "/d/build root/log.txt"' backend)" "quoted path"
unset CLAUDE_PROJECT_DIR
assert_block "absolute redirect with no project dir" "$HOOK" "$(payload_bash 'echo x > /d/build/log' backend)" "$gap"
# `>|` is the noclobber override, a redirect like any other. Without the `\|?` in
# the pattern its target hides behind the `|` and the redirect reads as
# targetless, i.e. as an exempt sink.
assert_block "noclobber override"     "$HOOK" "$(payload_bash 'echo x >| src/Foo.cs' backend)" "$gap"
assert_block "glued >| redirect"      "$HOOK" "$(payload_bash 'echo x >|src/Foo.cs' backend)"  "$gap"
# `-` means stdout to some commands, but `> -` writes a file named `-`.
assert_block "redirect into a file named -" "$HOOK" "$(payload_bash 'echo x > -' backend)"     "$gap"
# A glob metacharacter in an earlier, exempt target must not derail the scan of
# the later ones. The trim that advances past a match interpolates it *quoted*,
# which keeps it literal inside `${var#pattern}`; unquoted it would match
# nothing, leave `rest` unchanged and loop forever.
assert_block "redirect after a bracketed exempt target" "$HOOK" "$(payload_bash 'cmd > /tmp/out[1] > src/Foo.cs' backend)" "$gap"
assert_block "redirect after a starred exempt target"   "$HOOK" "$(payload_bash 'cmd > /tmp/a*b > src/Foo.cs' backend)"    "$gap"
assert_allow "bracketed exempt target alone"            "$HOOK" "$(payload_bash 'cmd > /tmp/out[1] > /dev/null' backend)"
assert_block "tee into a file"        "$HOOK" "$(payload_bash 'cat t | tee src/Foo.cs' backend)" "$gap"
assert_block "cp into the tree"       "$HOOK" "$(payload_bash 'cp /tmp/x src/Foo.cs' backend)"  "$gap"
assert_block "mv inside the tree"     "$HOOK" "$(payload_bash 'mv src/a.cs src/b.cs' backend)"  "$gap"
assert_block "patch"                  "$HOOK" "$(payload_bash 'patch -p1 < fix.diff' backend)"  "$gap"
# `git mv` is a rename recorded in the index, not a write: no bytes change, so no
# lane guard or formatter has anything to inspect, and the rename lands in a
# commit, where it is reviewed. The floor lets any agent run it, and crew's own
# no-git arm lets its workers run a plain one too. Bare `mv`/`cp` stay refused for
# everyone, and so does a forced `git mv`, which can clobber.
force="git mv -f/--force can overwrite"
assert_allow "lead git mv"                 "$HOOK" "$(payload_bash 'git mv BishopsArms.Members src/BishopsArms.Members' lead)"
assert_allow "lead git -C dir mv"          "$HOOK" "$(payload_bash 'git -C . mv src/a.cs src/b.cs' lead)"
assert_allow "lead git mv after &&"        "$HOOK" "$(payload_bash 'cd src && git mv a.cs b.cs' lead)"
assert_allow "lead two git mvs"            "$HOOK" "$(payload_bash 'git mv a b; git mv c d' lead)"
assert_allow "lead git mv -k (skip errors)" "$HOOK" "$(payload_bash 'git mv -k a b' lead)"
assert_allow "lead git mv of an mv-prefixed path" "$HOOK" "$(payload_bash 'git mv mvc/a.cs mvc/b.cs' lead)"
assert_block "lead git mv -f"              "$HOOK" "$(payload_bash 'git mv -f a b' lead)"       "$force"
assert_block "lead git mv --force"         "$HOOK" "$(payload_bash 'git mv --force a b' lead)"  "$force"
assert_block "lead git mv -kf (bundled)"   "$HOOK" "$(payload_bash 'git mv -kf a b' lead)"      "$force"
assert_block "lead git mv with a quoted -f" "$HOOK" "$(payload_bash "git mv '-f' a b" lead)"    "$force"
assert_block "forced git mv behind an allowed one" "$HOOK" "$(payload_bash 'git mv a b; git mv -f c d' lead)" "$force"
# The allowance covers the `git mv` token only: what follows is checked as before.
assert_block "bare mv behind an allowed git mv" "$HOOK" "$(payload_bash 'git mv a b && mv c d' lead)" "$gap"
assert_block "cp behind an allowed git mv"      "$HOOK" "$(payload_bash 'git mv a b && cp c d' lead)" "$gap"
assert_block "redirect behind an allowed git mv" "$HOOK" "$(payload_bash 'git mv a b > src/log' lead)" "$gap"
assert_block "lead bare mv"                 "$HOOK" "$(payload_bash 'mv src/a.cs src/b.cs' lead)" "$gap"
# The matched `git mv` text is interpolated quoted when it is masked and when the
# operands are cut out, so a glob metacharacter in it stays literal: the mask
# lands on that one token and a bare `mv` behind it is still seen.
assert_allow "git mv with a glob in a flag value" "$HOOK" "$(payload_bash 'git -C "*" mv a b' lead)"
assert_allow "git mv with globs in its operands"  "$HOOK" "$(payload_bash 'git mv "a*" "b[1]"' lead)"
assert_block "bare mv behind a glob-carrying git mv" "$HOOK" "$(payload_bash 'git -C "[" mv a b && mv c d' lead)" "$gap"
assert_block "forced glob-carrying git mv"          "$HOOK" "$(payload_bash 'git -C "*" mv -f a b' lead)"       "$force"
# Only a `git mv` at a command position is recognised; `-exec git mv` is not.
assert_block "git mv under find -exec"          "$HOOK" "$(payload_bash 'find . -name "*.cs" -exec git mv {} old/ \;' lead)" "$gap"
# A line start is a command position for this one allowance: the pattern reads
# the raw command, so two renames typed on two lines pass, where the flattened
# copy would have shown the generic check a bare `mv` on the second. What follows
# a `git mv` is still checked, on the same line or the next, and `git` on one
# line with `mv a b` on the next is two commands, not a rename.
nl=$'\n'
assert_allow "lead git mv on a second line"    "$HOOK" "$(payload_bash "cd src${nl}git mv a.cs b.cs" lead)"
assert_allow "lead two git mvs on two lines"   "$HOOK" "$(payload_bash "git mv a b${nl}git mv c d" lead)"
assert_allow "lead git mv on an indented line" "$HOOK" "$(payload_bash "cd src${nl}  git -C . mv a b" lead)"
assert_block "forced git mv on a second line"      "$HOOK" "$(payload_bash "git mv a b${nl}git mv -f c d" lead)" "$force"
assert_block "bare mv on a second line"            "$HOOK" "$(payload_bash "git mv a b${nl}mv c d" lead)"        "$gap"
assert_block "git and mv on separate lines"        "$HOOK" "$(payload_bash "git${nl}mv a b" lead)"                "$gap"
assert_block "git -C dir and mv on separate lines" "$HOOK" "$(payload_bash "git -C src${nl}mv a b" lead)"         "$gap"
# The floor does not decide WHOSE rename it is: an agent not on crew's roster is
# not crew's to refuse.
assert_allow "an agent not on crew's roster may git mv" "$HOOK" "$(payload_bash 'git mv src/a.ts src/b.ts' general-purpose)"
# A worker may run one plain `git mv` with relative paths, alone in the command,
# so the rename stays in the tree it was dispatched to. Anything wider is refused.
assert_allow "backend git mv"                      "$HOOK" "$(payload_bash 'git mv a b' backend)"
assert_allow "generalist git mv of nested paths"       "$HOOK" "$(payload_bash 'git mv src/a.cs src/b.cs' generalist)"
assert_allow "backend git mv -k into a directory"  "$HOOK" "$(payload_bash 'git mv -k a.cs b.cs old/' backend)"
assert_allow "backend git mv of a dotted path"     "$HOOK" "$(payload_bash 'git mv .github/a.yml .github/b.yml' backend)"
assert_block "backend git -C another repo mv"      "$HOOK" "$(payload_bash 'git -C /tmp/other mv a b' backend)" "$nogit"
assert_block "backend cd then git mv"              "$HOOK" "$(payload_bash 'cd /tmp/other && git mv a b' backend)" "$nogit"
assert_block "backend two git mvs in one command"  "$HOOK" "$(payload_bash 'git mv a b; git mv c d' backend)" "$nogit"
assert_block "backend git mv of an absolute path"  "$HOOK" "$(payload_bash 'git mv /tmp/other/a b' backend)" "$nogit"
assert_block "backend git mv out through .."       "$HOOK" "$(payload_bash 'git mv a ../other/a' backend)" "$nogit"
assert_block "backend git mv into ~"               "$HOOK" "$(payload_bash 'git mv a ~/a' backend)" "$nogit"
# shellcheck disable=SC2016  # the `$HOME` is command text, not to expand here
assert_block "backend git mv with an expansion"    "$HOOK" "$(payload_bash 'git mv a "$HOME/a"' backend)" "$nogit"
assert_block "backend git mv with a glob"          "$HOOK" "$(payload_bash 'git mv */config.yml archive/' backend)" "$nogit"
assert_block "backend git mv with a ? glob"        "$HOOK" "$(payload_bash 'git mv a?.cs b/' backend)" "$nogit"
assert_block "backend git mv with a bracket glob"  "$HOOK" "$(payload_bash 'git mv a[12].cs b/' backend)" "$nogit"
assert_block "backend git mv with a brace expansion" "$HOOK" "$(payload_bash 'git mv src/{a,b}.cs' backend)" "$nogit"
assert_block "backend env git mv"               "$HOOK" "$(payload_bash 'env git mv a b' backend)" "$nogit"
assert_block "backend git mv then git on a new line" "$HOOK" "$(payload_bash "git mv a b${nl}git push" backend)" "$nogit"
assert_block "backend git commit behind a git mv"  "$HOOK" "$(payload_bash 'git mv a b && git commit -m x' backend)" "$nogit"
assert_block "backend git mv -f is a write first"  "$HOOK" "$(payload_bash 'git mv -f a b' backend)" "$force"
assert_block "backend bare mv behind a git mv"     "$HOOK" "$(payload_bash 'git mv a b && mv c d' backend)" "$gap"
# The no-git check reads the flattened command, so a line of data is never refused.
assert_allow "backend prints a git mv in a quoted string" "$HOOK" "$(payload_bash "printf '%s\\n' 'header${nl}git mv a b'" backend)"
assert_allow "backend writes a git mv in a heredoc"       "$HOOK" "$(payload_bash "cat > /tmp/notes <<EOF${nl}git mv a b${nl}EOF" backend)"
# A backslash-newline is joined before the force check, as bash joins it.
assert_block "git mv -f after a line continuation" "$HOOK" "$(payload_bash "git mv \\${nl}-f a b" lead)" "$force"
# Exempt sinks and read-only uses of the same tools stay allowed: a guard that
# blocked `> /dev/null` would just be routed around.
assert_allow "redirect to /dev/null"  "$HOOK" "$(payload_bash 'dotnet build > /dev/null' backend)"
assert_allow "redirect to /dev/stderr" "$HOOK" "$(payload_bash 'echo x > /dev/stderr' backend)"
assert_allow "redirect to /dev/fd/2"   "$HOOK" "$(payload_bash 'echo x > /dev/fd/2' backend)"
# The /dev exemption is a list, not a glob: `/dev/*` would wave through a socket
# write and every device node.
assert_block "redirect to /dev/tcp"   "$HOOK" "$(payload_bash 'echo x > /dev/tcp/example.com/443' backend)" "$gap"
assert_block "redirect to a device node" "$HOOK" "$(payload_bash 'echo x > /dev/sda' backend)" "$gap"
assert_allow "fd dup (2>&1)"          "$HOOK" "$(payload_bash 'dotnet build 2>&1 | grep -c warning' backend)"
assert_allow "redirect under /tmp"    "$HOOK" "$(payload_bash 'dotnet build > /tmp/build.log 2>&1' backend)"
assert_allow "sed without -i"         "$HOOK" "$(payload_bash "sed 's/a/b/' src/Foo.cs | head -5" backend)"
assert_allow "sed -n (bounded read)"  "$HOOK" "$(payload_bash "sed -n '1,20p' src/Foo.cs" backend)"
assert_allow "quoted > in a pattern"  "$HOOK" "$(payload_bash 'grep -rn "a>b" src' backend)"
assert_allow "awk expression with >"  "$HOOK" "$(payload_bash "awk '\$3 > 5 {print}' report.txt" backend)"
assert_allow "Bash write in a no-agent session" "$HOOK" "$(payload_bash 'echo x > src/Foo.cs')"

# --- Fail closed on unparseable input -----------------------------------------
assert_block "non-JSON payload fails closed" "$HOOK" 'this is not json' "could not parse"

finish
