### homelab-llm.RQ002 - CLI Agent Edits Files End-to-End

**Description:**

The system MUST allow a CLI client (`aider`) running on a separate machine to instruct the self-hosted LLM to create, read, and modify source files via tool-use, with the resulting files being syntactically valid and behaviorally correct. This is the end-to-end functional contract of the stack: the inference endpoint plus the chosen client plus the chosen model produce working code, not just text. It is the user-visible value of the whole homelab.

**Parent Requirement:** N/A (personal homelab repository).

**Acceptance Criteria:**

- Issuing `aider --message "create hello.py with a greet(name) function and a pytest covering greet('World') == 'Hello, World'"` against the configured `${AIDER_MODEL}` produces a `hello.py` file in the working directory.
- The generated `hello.py` passes `python3 -m py_compile hello.py` (i.e., is valid Python).
- The generated `test_hello.py` passes `python3 -m pytest test_hello.py` with exit code `0`.
- A subsequent refactor turn issued via `aider` that does not change observable behavior keeps the previously passing pytest tests green.
- A single conversational turn for these simple tasks completes in under 180 seconds end-to-end on the reference hardware (Qwen2.5-Coder 7B, ~7 tok/s generation).
