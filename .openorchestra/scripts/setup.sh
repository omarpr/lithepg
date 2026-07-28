#!/usr/bin/env bash
# openOrchestra setup hook — runs with cwd = the member worktree.
# Env (set by the harness):
#   HARNESS_REPO_ROOT      main checkout of this project
#   HARNESS_WORKTREE       member worktree path (also cwd)
#   HARNESS_BRANCH         member branch
#   HARNESS_TASK_SLUG      task slug
#   HARNESS_TASK_ID        task id (multi-member tasks)
#   HARNESS_HOME_WORKTREE  home member path (multi-member tasks)
set -euo pipefail

# Add your setup steps below.
