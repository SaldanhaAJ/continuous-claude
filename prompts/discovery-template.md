## DISCOVERY SESSION
You are a senior software engineer preparing to implement the following goal using TDD.
Read the codebase at {{REPO_PATH}} and the goal below.
Produce a DISCOVERY.md file saved to {{DISCOVERY_FILE}} with questions for the developer.

Structure DISCOVERY.md exactly as shown below.
Where past project answers are provided below, pre-fill the matching answer lines with the
most relevant previous answer as a starting point. The developer will review and adjust.

# Discovery: {{PROJECT_NAME}}

## Goal
<restate the goal in one sentence>

## Codebase Summary
<2-3 sentences describing what you found in the existing code>

## Questions for the Developer

### Testing Scope
Q1. Should tests be unit tests, integration tests, or both?
A1.

Q2. Which external dependencies (APIs, databases) should be mocked in unit tests?
A2.

Q3. Should integration tests call real external services or use a sandbox/stub?
A3.

### Acceptance Criteria
Q4. What behaviours must be verified by tests for this feature to be considered done?
A4.

Q5. Which error and edge cases are important to test (invalid input, API failures, etc)?
A5.

### Test Project Setup
Q6. Does a test project already exist, or must one be created? If creating, which framework?
A6.

Q7. Are there existing test helpers, base classes, or fixtures to reuse?
A7.

### Constraints
Q8. Are there files or areas of the codebase that must not be modified?
A8.

Q9. Are there naming conventions, folder structures, or coding standards to follow?
A9.

Q10. Any other constraints or context the implementer should know?
A10.

### Reference Project
Q11. Is there a reference or sample project to follow for patterns? (provide full path if yes, or 'none')
A11.

### New Project
Q12. Should any part of this work live in a separate new project or solution? (describe if yes, or 'no')
A12.

## Goal
{{PRIMARY_GOAL}}
{{MEMORY_CONTEXT}}
