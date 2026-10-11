# Session prompt templates

Generic templates for the initialiser / worker pattern. Adapt the file names, commands and domain nouns; keep the structure.

## Shared system prompt fragment (both session types)

```
<long_running_work>
You work in sessions. Each session has no memory of previous ones; the files below are the
shared memory. Your context may be compacted during a session; keep going after compaction
rather than wrapping up early.

State files:
- SPEC.json       the list of work items. You may change an item's "passes" flag from false to
                  true after you have verified it end-to-end. You must never remove, reword or
                  weaken an item or its verification steps.
- PROGRESS.md     append-only log: one entry per session with what was done, verified, and left open.
- PLAN.md         the current plan; update it when the approach changes.
- init.sh         starts the system for testing. Never re-derive how to run it; use this script.

Clean state means: no known major bugs, code is orderly and documented, the next session can
start a new item without cleanup. Always leave a clean state before ending.
</long_running_work>
```

## Initialiser session (user prompt)

```
Set up this project for long-running work.
1. Read the request in REQUEST.md.
2. Expand it into SPEC.json: one entry per small, independently verifiable item with
   "category", "description", "steps" (2-6 short actions a tester would take to verify it)
   and "passes": false. Prefer many small items over few large ones.
3. Write init.sh that installs dependencies and starts the system for testing.
4. Create PROGRESS.md with a first entry describing what you set up.
5. Write PLAN.md with the intended architecture and order of work.
6. Make an initial git commit.
Do not implement any items in this session.
```

## Worker session (user prompt)

```
Continue the project.
Start: run `pwd`; read `git log --oneline -20`, PROGRESS.md and PLAN.md; read SPEC.json and pick
the highest-priority item with "passes": false; run ./init.sh and a basic end-to-end smoke test;
fix anything broken before new work.
Work: implement exactly one item.
Verify: test it the way a user would (drive the real interface, not only unit tests). Only then set
"passes": true for that item.
End: commit with a descriptive message, append a PROGRESS.md entry (done / verified / open
questions), confirm the state is clean. Stop after one item.
```

## Delegation to subagents

The delegation template and worker return contract live in the `multi-agent-orchestration` skill (`references/lead-agent-prompt.md`).
