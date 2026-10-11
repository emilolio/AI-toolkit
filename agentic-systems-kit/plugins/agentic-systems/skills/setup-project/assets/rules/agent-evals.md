# Evaluation conventions

Applies whenever a prompt, tool, model, harness setting or orchestration pattern changes, and whenever a new capability is planned. For the reasoning, load the `agent-evals` skill.

- No change to prompts, tools or harness ships without running the eval suite before and after. Report the delta, not only the new score.
- Start early with 20–50 tasks drawn from real usage and real failures; a small set is enough while changes have large effects. Grow it from production transcripts.
- Tasks are unambiguous (two domain experts reach the same verdict), multi-step with context and a goal, and each has a reference solution that passes all graders.
- Grade the outcome (final state, final answer), not the path. Tool-sequence checks are brittle and punish valid strategies.
- Grader preference order: deterministic code → LLM judge with a structured rubric, one dimension per judge, an "unknown" escape hatch → human review for calibration and spot checks.
- Keep balanced sets: tasks where a behaviour should fire and tasks where it should not.
- Separate capability evals (a hill to climb) from regression evals (should stay near 100%). Saturated capability evals graduate into regression.
- Run several trials per task in isolated environments. Report pass@k for "at least one success" use cases and pass^k for customer-facing reliability.
- Track efficiency alongside accuracy: turns, tool calls, tokens, cost, latency, error rate.
- Never trust a score without reading transcripts. Sample transcripts weekly in production.
- Practise eval-driven development: write the eval for a planned capability before building it.
