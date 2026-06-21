## YOUR TASK FOR THIS ITERATION - [RED PHASE]
{{CURRENT_TASK}}

## TDD RED PHASE RULES
- Write ONLY the test(s) described above. Do not write any implementation code.
- The test must compile and reference the interface or class it will test.
- Run the test and CONFIRM it fails (compile error or test failure -- either is correct for RED).
- Do not fix the failure. A failing test is the goal of this phase.
- Stop as soon as the test exists and is confirmed failing.
- IMPORTANT: The task description states an EXPECTED failure reason. Before writing the test,
  read the codebase to verify whether that reason is accurate. If the actual failure reason
  differs (e.g. the class already exists, or the real error is different), proceed with the
  correct failure -- do NOT make unnecessary changes to force the stated reason. Record the
  real failure reason in SHARED_TASK_NOTES.md so the GREEN task has accurate context.
<!-- VERIFY -->
## MANDATORY BEFORE FINISHING
1. Run dotnet test (or dotnet build if the project will not compile yet).
2. Confirm the new test FAILS or does not compile -- this is the expected RED state.
3. Replace SHARED_TASK_NOTES.md at {{NOTES_FILE}} with ONLY this iteration's notes:
   - What test(s) you wrote and what they verify
   - The ACTUAL failure reason (which may differ from the task description if the codebase
     state differed from the plan's assumption -- note any discrepancy explicitly)
   - The exact test run output confirming RED state (failure or compile error)
   - The test method names so the next iteration knows what to make pass
