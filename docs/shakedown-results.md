# Shakedown results — aider + Qwen2.5-Coder 7B

End-to-end shakedown of aider + Qwen2.5-Coder 7B on hidra. Goal: validate the stack handles non-trivial multi-file tasks before investing in gateway / RPi infrastructure.

## Setup

aider 0.86.2 on the Mac client, Ollama 0.30.6 on hidra, Qwen2.5-Coder 7B Q4_K_M served via the host-bound systemd unit. The exact command driving every turn:

```bash
OLLAMA_API_BASE=http://192.0.2.143:11434 \
aider --model ollama_chat/qwen2.5-coder:7b \
      --edit-format whole \
      --no-show-release-notes \
      --auto-commits --yes-always
```

Working directory: a clean `/tmp/aider-shakedown/` with `git init`, an initial `README.md` committed, and nothing else. Five tasks were chained in order; aider was kept resident across turns so its conversational context carried over.

## Task by task

### Task 1 — Create `tasks.py` with a `TaskList`

**Prompt:**

> Create a `tasks.py` module that defines a `TaskList` class using `@dataclass`. Each task has `title: str`, `priority: str` (one of `"low"`, `"medium"`, `"high"`). Validate priority in `__post_init__` and raise `ValueError` for any other string. Add full type hints.

**Output (synthesized):** a single `tasks.py` with a `Task` dataclass, a `TaskList` wrapper holding `list[Task]`, an `add_task(title, priority)` method, and `__post_init__` raising `ValueError` for invalid priority strings. Type hints clean throughout.

**Metrics:** 89 s, 845 tokens sent / 328 received.

**Verdict:** ✓ Correct on first turn. File compiles, manual smoke check passes.

### Task 2 — Add `test_tasks.py` with 6 pytest tests

**Prompt:**

> Add `test_tasks.py` next to `tasks.py` with 6 pytest tests covering: empty list, adding one task, adding multiple, invalid priority raises ValueError, removing by title, and listing by priority.

**Output (synthesized):** `test_tasks.py` with the 6 tests requested. The invalid-priority test uses `pytest.raises(ValueError)` on `priority="urgent"` (an invalid string), which is exactly the intent.

**Metrics:** 110 s, 1.0k tokens sent / 415 received. Equivalent re-run: same aider command, prompt as above.

**Verdict:** ✓ 6/6 pass on `pytest -q`.

### Task 3 — Refactor priority to `Enum`, keep backward-compat with strings

**Prompt:**

> Refactor `tasks.py` so `priority` is a `Priority` enum (`LOW`, `MEDIUM`, `HIGH`). Keep backward-compat: callers that pass a string like `"low"` should still work. Update `test_tasks.py` to use the enum where natural. Multi-file edit.

**Output (synthesized):** `tasks.py` now defines `class Priority(Enum)`, and `__post_init__` accepts both `Priority` instances and strings (mapping strings via `Priority[priority.upper()]`). The model also rewrote `test_tasks.py` to use `Priority.HIGH` etc. — and **silently mutated `test_add_task_invalid_priority`** by replacing the original `priority="urgent"` (a deliberately invalid string that should raise `ValueError`) with `priority=Priority.HIGH` (a perfectly valid value). The test now asserts `ValueError` is raised on a valid input, so pytest reports `DID NOT RAISE`.

**Metrics:** 173 s, 1.4k tokens sent / 768 received.

**Verdict:** ✗ Bug introduced. The refactor is mostly correct but the model failed to **understand the intent of the test** — it changed the literal token (`"urgent"` → `Priority.HIGH`) without realising the test's whole purpose was to feed invalid input. This is not a syntax error, it's a comprehension-of-intent failure.

### Task 4 — Fix the test the model just broke

**Prompt:**

> `test_add_task_invalid_priority` is failing with `DID NOT RAISE`. The test should pass an invalid priority and assert ValueError. Fix it.

**Output (synthesized):** the model put back an invalid string — `priority="invalid"` — which is the right shape. But pytest still fails: this time with `KeyError: 'INVALID'` instead of `ValueError`. The model did not realise that the new `Priority[priority.upper()]` lookup raises `KeyError` on unknown names, not `ValueError`. The bug just moved one layer down.

**Metrics:** 108 s, 1.4k tokens sent / 425 received.

**Verdict:** ✗ Bug moved, not fixed. The test now exercises the right input but `tasks.py` raises the wrong exception type.

### Task 5 — Fix `tasks.py` with an explicit hint

**Prompt:**

> The problem is in `tasks.py`: `Priority[priority.upper()]` raises `KeyError`, not `ValueError`. Wrap it so unknown strings raise `ValueError` with a clear message.

**Output (synthesized):** model wraps the lookup with `try: ... except KeyError: raise ValueError(f"invalid priority: {priority!r}")`. Clean, idiomatic, message is informative.

**Metrics:** 102 s, 1.4k tokens sent / 396 received.

**Verdict:** ✓ 6/6 pass. With an explicit hint pointing at the file *and* the failure mode, the model fixes it on the first try.

**Totals across the chain:** ~9.5 minutes wall time, 4/5 tasks resolved autonomously (task 4 needed the human hint that became task 5).

## Lessons learned

**What works well with aider + Qwen 7B:**

- ✓ Creating new code from a clear spec (tasks 1, 2).
- ✓ Generating pytest test scaffolds with reasonable coverage.
- ✓ Localized edits when the prompt names the file *and* the symptom (task 5).
- ✓ Auto-commits with `--yes-always` keep the trail clean for `git bisect` if a turn breaks something.

**What requires supervision:**

- ⚠ Refactors that depend on understanding **intent** (not just substituting tokens). Task 3 is the canonical failure: every visible code change was syntactically valid but the test no longer tested what it was meant to test.
- ⚠ Dead imports / leftover code after a refactor — the model rarely cleans these up.
- ⚠ Some fixes need 2–3 turns and human triage to land.
- ⚠ Speed: 90–180 s per turn means a 5-turn session is ~10 min wall time even when nothing goes wrong.

**Best practices extracted:**

- 📌 Run pytest after **every** aider turn and feed the failure output back as the next prompt. The model fixes much faster with a real traceback than with hand-summarized symptoms.
- 📌 For complex refactors, slice them into smaller turns — one concept at a time. A single "refactor X to enum and keep backward-compat and update tests" turn is at the edge of what 7B can hold coherently.
- 📌 Consider `aider --architect` (planner + editor with two models — e.g. 7B planning + 3B editing) for multi-file work. On the v0.5 roadmap.

## Reproducibility

The first task of this shakedown is captured as a CI-friendly automated check at `tests/test_RQ002_aider_writes_file_and_pytest_passes.sh` — it runs aider against the same prompt, asserts a file is written, and runs pytest in the resulting workspace. Tasks 2–5 are not automated (they exercise model comprehension, not stack plumbing) and remain manual.

## Comparison vs cloud Claude Code

The same enum refactor (task 3 above) run in Claude Code against Anthropic Sonnet 4.6 lands in ~20–30 s, comprehends the *intent* of `test_add_task_invalid_priority` on the first turn, and does not touch the test's invalid-input literal.

aider + Qwen 7B local needed 9.5 minutes across 5 turns to reach the same final state.

The honest takeaway is balanced: the local stack is viable as a **complement** to a cloud agent, not a **replacement** for it. The properties it does buy you — privacy, no per-turn cost, no cloud dependency — line up well with specific use cases:

- non-critical or exploratory work where wall time doesn't matter,
- code you don't want to send to a third-party endpoint,
- long-running batch edits over private repos,
- workflows where the cost of a cloud subscription dominates.

For tight feedback loops or refactors where intent comprehension matters, cloud Claude Code remains the right tool. The two stacks coexist; they don't compete one-to-one.
