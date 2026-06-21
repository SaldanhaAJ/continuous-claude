## TASK PLAN DEPENDENCY REPAIR
You are a senior software engineer. A dependency review has found violations in the TDD task plan below.
Your job is to produce a corrected version of the task plan that fixes every ISSUE listed in the review.

## Repair Rules
1. Fix ONLY the violations listed in the review. Do not restructure tasks that are marked OK.
2. Allowed fixes: reorder tasks, split a task into two, move a type/file creation to an earlier task.
3. Do NOT change task descriptions beyond what is required to resolve the violation.
4. Do NOT add new tasks unless a split is the only way to resolve a forward-reference.
5. Re-number tasks sequentially after any reordering or splits.
6. Preserve all [x] completed tasks exactly as-is at the top of the list - do not reorder them.
7. Output ONLY the corrected task plan in the exact same markdown checklist format - no commentary.

## DEPENDENCY REVIEW (violations to fix)
{{REVIEW_CONTENT}}

## CURRENT TASK PLAN
{{TASK_PLAN}}
