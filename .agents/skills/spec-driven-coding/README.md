# spec-driven-coding

> Enforce Dewey's Superpowers-first spec, plan, TDD, and verification workflow.

## What it does

`spec-driven-coding` keeps implementation from starting before the requirement is
aligned. It uses the Superpowers brainstorming, spec, planning, TDD, debugging, and
verification workflows when available, provides a lightweight path for simple
bugfixes, and reminds the agent to update specs when requirements change mid-build.

## When it triggers

- Starting a new feature or behavior change
- Multi-step implementation work
- Ambiguous requirements that need design agreement
- Simple bugfixes that still need debugging, regression tests, and verification
- Requirement changes discovered during coding

## Installation

```bash
npx skills add https://github.com/deweyou/agents --skill spec-driven-coding
```

## Source

This skill is maintained in `deweyou/agents` and indexed by `deweyou-cli agent update`.
