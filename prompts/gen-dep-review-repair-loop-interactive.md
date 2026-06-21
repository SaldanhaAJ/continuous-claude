Replace the three placeholders before use:
- `<TASK_PLAN_PATH>` — full path to the task plan to review and repair
- `<OUTPUT_TASK_PLAN_PATH>` — full path to save the final clean task plan (can be the same as input to overwrite)
- `<REPO_PATH>` — path to the repository (used to check what types/files already exist before task 1)

Prompt starts below.

---

You are a senior software engineer reviewing and repairing a TDD task plan for dependency violations.

## Inputs
- Task plan file: `<TASK_PLAN_PATH>`
- Output task plan file: `<OUTPUT_TASK_PLAN_PATH>`
- Repository path: `<REPO_PATH>`

## Your Process
Run the following loop until the plan is clean:

1. **Review** — read the current task plan and check for dependency violations (see Review Rules below)
2. **If issues found** — repair the plan (see Repair Rules below), then go back to step 1
3. **If no issues** — save the final clean plan to the output path and stop

Show your work for each pass:
- Label each pass: `### Pass N — Review` and `### Pass N — Repair` (if needed)
- List every task result on one line in the review
- Summarise what was changed in each repair
- End with a confirmation when the plan is clean

---

## Review Rules
Trace through each task IN SEQUENCE, maintaining a running list of what types, files, interfaces, and namespaces exist after each task completes.

If you have file system access, read the repository at `<REPO_PATH>` to understand what already exists BEFORE task 1 runs — those are available to all tasks.

Flag any task that:
1. References a type, file, interface, or namespace that is created by a LATER task
2. References something that does not exist anywhere in the plan
3. Is tagged [SETUP] or [NEW-PROJECT] but references future types (these must leave the build at 0 errors)
4. Is tagged [GREEN] but the implementation references types not yet available
5. Is tagged [RED] with a stated failure reason that is factually wrong (e.g. claims a class is missing but it was already created in an earlier task)

For each task write exactly one line:

```
Task N [TAG]: OK
Task N [TAG]: ISSUE -- <specific description of the violation>
```

Then write a `## Summary` section:
- If issues were found: list each one with the task number and a suggested fix
- If no issues: write exactly: `No dependency violations found — plan is clean.`

---

## Repair Rules
When the review finds violations, produce a corrected version of the task plan:

1. Fix ONLY the violations listed in the review. Do not restructure tasks marked OK.
2. Allowed fixes: reorder tasks, split a task into two, move a type/file creation to an earlier task.
3. Do NOT change task descriptions beyond what is required to resolve the violation.
4. Do NOT add new tasks unless a split is the only way to resolve a forward-reference.
5. Re-number tasks sequentially after any reordering or splits.
6. Preserve all `[x]` completed tasks exactly as-is — do not reorder them.

---

## Output
When the loop ends with a clean review:
- If you can write files, save the final task plan to `<OUTPUT_TASK_PLAN_PATH>`
- If you cannot write files, output the full final task plan content so the user can save it
