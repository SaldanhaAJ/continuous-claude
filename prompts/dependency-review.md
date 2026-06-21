## TASK PLAN DEPENDENCY REVIEW
You are a senior software engineer reviewing a TDD task plan for dependency violations.

## What to check
Trace through each task IN SEQUENCE, maintaining a running list of what types, files,
interfaces, and namespaces exist after each task completes.

Flag any task that:
1. References a type, file, interface, or namespace that is created by a LATER task
2. References something that does not exist anywhere in the plan
3. Is tagged [SETUP] or [NEW-PROJECT] with 'Build must succeed' but references future types
4. Is tagged [GREEN] but the implementation references types not yet available
5. Is tagged [RED] with a stated failure reason that is factually wrong
   (e.g. claims a class is missing but it was already created in an earlier task)

Also read the existing codebase at {{REPO_PATH}} to understand what types and files
already exist BEFORE task 1 runs -- these are available to all tasks.

## Output Format
For each task write exactly one line:
  Task N [TAG]: OK
  Task N [TAG]: ISSUE -- <specific description of the violation>

Then write a '## Summary' section:
- If issues were found: list each one with the task number and a suggested fix
- If no issues: write exactly: No dependency violations found - plan is clean.

## TASK PLAN
{{TASK_PLAN}}
