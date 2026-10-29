#!/usr/bin/env bash
# shellcheck source=evals/grade.sh
# shellcheck disable=SC1091,SC2329  # the helpers below run through `criterion`
source "$EVAL_ROOT/grade.sh"

job_class() { grep -rhoE --exclude-dir=bin --exclude-dir=obj 'class [A-Za-z]+ : ScheduledJobBase' src | head -n 1 | awk '{print $2}'; }
job_is_tested() { local job; job="$(job_class)" && [ -n "$job" ] && has "(^|[^A-Za-z0-9_])$job([^A-Za-z0-9_]|$)" tests; }

standard
criterion "a ScheduledJobBase subclass" has ': ScheduledJobBase' src
criterion "it has a [ScheduledJob] GUID" has '\[ScheduledJob\(.*GUID = "[0-9a-fA-F-]{36}"' src
criterion "no ScheduledPlugIn left from CMS 12" lacks 'ScheduledPlugIn' src
criterion "the job has tests" job_is_tested
verdict
