# git-delivery

> Manage Dewey's branch, commit, push, PR, and CI follow-up workflow.

## What it does

`git-delivery` handles the git lifecycle around development work. At task start it
checks the current branch, protects dirty work, and fetches the primary branch
without moving the worktree unless the user asks for branch preparation. At task
finish it runs repo memory, verification, commit, push, PR creation, and CI
follow-up.

## When it triggers

- Starting a new coding task or implementation session
- Preparing an explicit new task branch or parallel worktree
- "提交吧", "commit it", "发一下", "ship it"
- "开 PR", "push", "提交并建 PR"
- After a PR is opened and CI needs monitoring

## Installation

```bash
npx skills add https://github.com/deweyou/agents --skill git-delivery
```

## Source

This skill is maintained in `deweyou/agents` and indexed by `deweyou-cli agent update`.
