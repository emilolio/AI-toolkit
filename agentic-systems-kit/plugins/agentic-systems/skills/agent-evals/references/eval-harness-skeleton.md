# Minimal eval harness skeleton and judge rubric template

Language-agnostic structure; implement in whatever your project uses.

## Task file (one per task)

```json
{
  "id": "calendar-003",
  "suite": "scheduling-regression",
  "input": {
    "prompt": "Find a 30-minute slot next week for me, Dana and Lee, book a room, and attach the notes from the kickoff.",
    "fixtures": "fixtures/calendar-003/"
  },
  "reference_solution": "fixtures/calendar-003/expected_state.json",
  "graders": [
    {"type": "state", "check": "event exists with 3 attendees, duration 30, room booked, attachment present"},
    {"type": "transcript", "max_turns": 12, "max_tool_calls": 15},
    {"type": "judge", "rubric": "rubrics/scheduling.md", "dimensions": ["correctness", "communication"]}
  ],
  "trials": 3,
  "tags": ["should-fire:calendar_find_free_slots"]
}
```

## Harness loop

```
for task in suite:
    for trial in range(task.trials):
        env = fresh_environment(task.input.fixtures)      # isolated: no shared files, caches, git, memory
        transcript = run_agent(task.input.prompt, env, budget=task.budget)
        results = [grade(g, env, transcript) for g in task.graders]
        record(task.id, trial, transcript, results, usage(transcript))   # tokens, calls, cost, latency
        destroy(env)
aggregate: per-task pass rate, pass@k, pass^k, efficiency distributions
fail CI if any regression-suite task drops below its threshold
```

## Judge rubric template (one dimension per judge call)

```
You are grading ONE dimension of an agent transcript: <dimension>.

<definition>
<what this dimension means, in 2-4 sentences, with what a 1.0 and a 0.0 look like>
</definition>

<reference>
<reference solution or expected state, if any>
</reference>

<transcript>
<the transcript or final output>
</transcript>

Score from 0.0 to 1.0. If you cannot determine the score from the evidence, answer "unknown".
Respond as JSON: {"score": <number or "unknown">, "reasoning": "<2-3 sentences citing evidence>"}
```

Calibrate: grade 30–50 transcripts with humans and the judge; require agreement before using the judge unattended; re-calibrate when the agent or the judge model changes.

## Minimum metrics to log per trial

accuracy (per grader), pass/fail, turns, tool calls, tool errors, input tokens, output tokens, cache reads, cost, wall-clock, time to first token.
