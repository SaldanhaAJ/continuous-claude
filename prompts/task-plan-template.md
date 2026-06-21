## TDD TASK PLAN REQUEST
You are a senior software engineer. Generate a TDD-ordered task plan for the goal below.

## TDD Rules - MANDATORY
1. The test project must be created and added to the solution BEFORE any feature work.
2. Every feature must follow RED then GREEN order:
   - [RED] task: write a failing test that defines the expected behaviour. Confirm it FAILS.
   - [GREEN] task: write minimum implementation to make that test pass. Confirm tests PASS.
3. No [GREEN] task may appear without a preceding [RED] task for the same feature.
4. Tag every task with [RED], [GREEN], [SETUP], or [NEW-PROJECT: name] at the start.
5. Each task must touch no more than 1-3 files.
6. Each task description must be fully self-contained: include file paths, class names,
   method names, and any other specific details needed.
7. [SETUP] and [NEW-PROJECT] tasks MUST leave the solution buildable (0 compile errors) when
   complete. Never reference a type, interface, or namespace in a SETUP task that does not
   already exist or is not created within that same task.
   - If a DI registration file (e.g. DIConfig.cs) needs to wire up an interface, the interface
     must be created in the SAME task or an EARLIER task -- not a later one.
   - If this is not possible, SPLIT the work: one SETUP task creates the stub types, the next
     SETUP task adds the registrations that reference them.
8. [RED] tasks are the ONLY tasks allowed to leave the build failing. All [SETUP], [GREEN],
   and [NEW-PROJECT] tasks must end with `dotnet build` returning 0 errors AND all existing
   tests passing.
9. For every [RED] task you write, you MUST verify the stated failure reason against the actual
   codebase BEFORE writing it into the plan. Do not assume -- read the files.
   - If a class or type already exists and is accessible, do NOT say it is missing.
   - The failure reason must be the REAL reason the test will fail at that point in the sequence
     (e.g. method throws NotImplementedException, assertion fails on returned value, etc.).
   - A wrong failure reason in the plan will mislead the next iteration into making unnecessary
     changes to 'fix' something that was never broken.

## Output Format
Output ONLY a markdown checklist in this exact format with no extra commentary:

# Task Plan

## Goal
<restate the goal in one sentence>

## Tasks
- [ ] 1. [SETUP] <task description>
- [ ] 2. [SETUP] <task description>
- [ ] 3. [RED] Write failing test for <feature>: <specific test details>
- [ ] 4. [GREEN] Implement <feature> to pass tests: <specific implementation details>
- [ ] 5. [RED] Write failing test for <next feature>: ...
- [ ] 6. [GREEN] Implement <next feature>: ...

## Goal
{{PRIMARY_GOAL}}

## Discovery Answers
{{DISCOVERY_CONTEXT}}

## Project Structure
Read the repo at {{REPO_PATH}} before writing the plan.
{{SAMPLE_SECTION}}{{NEW_PROJECT_SECTION}}
