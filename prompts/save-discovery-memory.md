Read the completed discovery file at {{DISCOVERY_FILE}}.
Extract only the answered questions (lines starting with A1., A2., etc. that have content).
Append them to the shared memory file at {{MEMORY_FILE}}.

Format the entry exactly as follows - do not change the existing content of the memory file:

## [{{DATE}}] Project: {{PROJECT_NAME}}

### Testing Scope
- Q: Should tests be unit tests, integration tests, or both?
  A: <answer from A1>

- Q: Which external dependencies should be mocked?
  A: <answer from A2>

- Q: Should integration tests call real services or use a sandbox?
  A: <answer from A3>

### Acceptance Criteria
- Q: What behaviours must be verified by tests?
  A: <answer from A4>

- Q: Which error and edge cases are important?
  A: <answer from A5>

### Test Project Setup
- Q: Does a test project exist or must one be created?
  A: <answer from A6>

- Q: Are there existing test helpers or fixtures to reuse?
  A: <answer from A7>

### Constraints
- Q: Files or areas that must not be modified?
  A: <answer from A8>

- Q: Naming conventions or coding standards?
  A: <answer from A9>

- Q: Other constraints or context?
  A: <answer from A10>

### Reference Project
- Q: Is there a reference or sample project to follow?
  A: <answer from A11>

### New Project
- Q: Should any part live in a separate new project?
  A: <answer from A12>

---

If {{MEMORY_FILE}} does not exist, create it with this header first:
# Discovery Memory
This file accumulates answers from past discovery sessions to pre-fill future projects.

---
