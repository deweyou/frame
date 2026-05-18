---
name: git-delivery
description: >
  Manage Dewey's git delivery workflow. Use this skill at the start of a coding
  session to inspect the current branch, protect dirty work, and fetch the primary
  branch without moving the worktree unless the user asks for a new branch. Also
  use when the user says
  "提交吧", "commit it", "发一下", "ship it", "开 PR", "push", or asks to finish
  work, so the agent runs memory check, verification, intentional staging, commit,
  base-branch conflict check, rebase when safe, push, PR creation or exact blocker
  reporting, and CI follow-up. Always protect dirty work: never discard, overwrite,
  or stage unrelated files.
---

# Git Delivery

Run the repository delivery flow without making the user spell out every git step.

When invoked, make the safety and delivery decisions explicit. Reviewers need to
see the branch choice, dirty-work protection, intended staging boundary, PR
creation or blocker, base-branch conflict/rebase status, and CI repair consent
policy.

## Start Of Work

Use this section when beginning a new implementation task.

1. Check `git status --short` and the current branch.
2. Identify the primary branch, usually `main`.
3. Fetch the latest remote state for the primary branch, for example
   `git fetch origin <primary>`, without switching branches.
4. Stay on the current branch by default. State the current branch and the fetched
   baseline, such as `origin/main`.
5. Create a dedicated task branch only when the user explicitly asks to prepare a
   branch, start a fresh branch, or similar. If creating a branch, branch from the
   fetched baseline when the worktree is clean and the user has not asked to
   continue from the current branch.
6. For parallel work, prefer a separate worktree or an explicit new branch instead
   of moving the existing worktree away from an active task.
7. Do not discard or overwrite existing user changes. If local changes block a safe
   branch creation or worktree setup, stop and ask how to handle them.

If the user says "continue here", "use this branch", or similar, stay on the current
branch and state that choice. If the user only asks to start implementation, do not
switch branches unless they also ask for branch preparation.

Always report the dirty-work decision:

- `dirty_work`: none, protected, or blocks branch creation/worktree setup
- `unrelated_files`: left untouched and unstaged
- `base_sync`: fetched primary branch, already current, or blocked with reason
- `branch_action`: stayed, created branch, created worktree, or blocked with reason

## Finish Work

Use this section when the user asks to commit, push, open a PR, or ship the work.

1. Inspect `git status --short`.
2. Run `repo-memory` before committing when that skill is available.
3. Run relevant verification commands for the changed files.
4. Stage only intended files.
5. Commit with a concise conventional message when the repo uses conventional
   commits, otherwise match local history.
6. Fetch the target merge branch, usually `origin/main`, and check whether the
   current branch can cleanly merge or rebase onto it.
7. If the branch is behind or would conflict with the target merge branch, rebase
   onto the target branch before pushing when the worktree is clean and the rebase
   is safe. Resolve straightforward conflicts when the intended result is clear.
   If conflicts are non-trivial, stop and report the conflicting files and exact
   blocker.
8. After any successful rebase or conflict resolution, re-run relevant verification
   before pushing. Always say `verification_after_rebase`: commands run, not needed,
   or blocked with reason.
9. Push the branch. Use `--force-with-lease` only after a rebase rewrote the branch
   and only for the task branch.
10. Open a pull request using the repository's normal tool or hosting CLI. If a PR
   cannot be created, report the exact blocker, such as missing auth, missing remote,
   detached HEAD, no GitHub CLI, or no network.
11. Summarize the problem, solution, and verification in the PR body.

Never include unrelated dirty files in the commit. If unrelated changes exist, leave
them unstaged and call them out.

## Base Branch Conflict Check

Before pushing or opening a PR, always check the branch against the intended merge
base:

1. Fetch the base branch.
2. Inspect whether the head branch is behind, diverged, or merge-conflicting.
3. Prefer `git rebase origin/<base>` for a clean task branch.
4. If the rebase conflicts, inspect the conflict files. Resolve only when the
   intended result is clear from the code and user request.
5. After resolving conflicts, continue the rebase, rerun verification, and push with
   `--force-with-lease`. The rebase workflow is not complete until
   `verification_after_rebase` has been run or an exact blocker is reported.
6. If conflict resolution is ambiguous, abort or pause safely and report the exact
   files plus the decision needed from the user.

Always report:

- `base_branch`: target branch checked
- `conflict_check`: clean, rebased, conflicted-resolved, or blocked
- `rebase`: not needed, completed, or blocked
- `conflict_files`: list of files, or `none`
- `verification_after_rebase`: commands run, not needed, or exact blocker

Always report the finish-work boundary:

- `repo_memory`: run, skipped with reason, or unavailable
- `verification`: commands run, or exact blocker
- `staging`: intended files only; unrelated files left unstaged
- `commit`: hash and message, or exact blocker
- `base_conflict_check`: base branch, result, rebase status, conflict files
- `verification_after_rebase`: commands run after rebase, not needed, or exact blocker
- `push`: destination, or exact blocker
- `pr`: URL, or exact blocker

## CI Follow-Up

After a PR is opened or a pushed branch has CI:

- Create a follow-up automation or reminder to check CI when the environment
  supports it.
- If CI fails, tell the user what failed and ask before starting any repair work.
- When subagents are available and the user approves, run CI repair in a separate
  branch or isolated workstream so the main delivery flow stays readable.

Never silently fix CI after a failure. The next action after a CI failure is:
"CI failed for <job>. Do you want me to start a separate repair pass?"

## Output

Report:

- branch used or created
- dirty-work protection and unrelated-file handling
- commit hash and message
- push destination
- PR URL when created, or exact PR blocker
- verification commands run
- CI follow-up status
- whether CI repair needs user approval
