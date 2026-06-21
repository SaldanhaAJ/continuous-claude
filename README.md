# Continuous Claude

A menu-driven PowerShell tool that runs [Claude Code](https://claude.ai/code) in a continuous
Test-Driven Development loop — automatically building prompts, running Claude, reviewing the
output, and committing — one task at a time.

## How it works

1. **Discovery** — Claude reads your codebase and generates a questionnaire. You fill in answers
   about testing scope, mocking strategy, acceptance criteria, and constraints. Answers accumulate
   across projects and pre-fill future sessions.

2. **Task Plan** — Claude converts your discovery answers into a TDD checklist tagged by phase:
   `[SETUP]`, `[RED]` (write failing test), `[GREEN]` (implement to pass), `[NEW-PROJECT]`.

3. **The loop** — For each task, the script builds a prompt, runs Claude, then sends the git diff
   to Claude for a structured code review. Action items trigger another pass. After three consecutive
   failed fix attempts, a break-loop diagnostic runs.

4. **Commit** — When the review is clean the script commits, marks the task done, and advances
   to the next. Run one task at a time or use the auto-loop (Option 9) for unattended batches.

## Prerequisites

- **Windows** — the script uses PowerShell 5.1+, `notepad.exe`, and Windows audio/notification APIs
- **[Claude Code CLI](https://docs.anthropic.com/claude-code)** — install and authenticate before use
- **Git** — must be on PATH
- **Your tech stack's build/test toolchain** — the default prompt templates reference `dotnet build`
  and `dotnet test`; customize the templates in the `prompts/` folder for your stack

## Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/your-username/continuous-claude
cd continuous-claude

# 2. Create your project goal file
copy prompt.txt.example prompt.txt
notepad prompt.txt   # describe what you want to build

# 3. (Optional) Edit appsettings.json to point at your worklog folder and repo
#    Paths are relative to the script folder by default — absolute paths also work
notepad appsettings.json

# 4. (Optional) Customize prompt templates for your tech stack
#    Edit files in the prompts/ folder — or leave them as-is for .NET projects

# 5. Run the script
.\continuous-claude.ps1

# Or double-click CC.bat — no terminal setup required
```

When the script starts you will see:

```
===========================================
 Continuous Claude - Manual Iteration Tool
===========================================

Repo path (ENTER for C:\Repos\MyProject):
Worklog path (ENTER for C:\Repos\continuous-claude\claude-worklog):
Prompts path (ENTER for C:\Repos\continuous-claude\prompts):
Project name (ENTER for MyProject):
```

| Prompt | What to enter |
|--------|--------------|
| **Repo path** | Full path to the git repository Claude will read and write code in. This is your target project — not the continuous-claude folder itself. |
| **Worklog path** | Folder where task plans, iteration notes, and code reviews are saved. Defaults to `claude-worklog\` next to the script. Each project gets its own subfolder inside here. |
| **Prompts path** | Folder containing the Claude prompt templates. Leave as-is unless you have moved the `prompts/` folder elsewhere. |
| **Project name** | A short name for this work session (e.g. `MyFeature`, `PaymentService`). Used as the worklog subfolder name and git branch suffix — special characters are replaced with underscores automatically. |

Press **ENTER** at any prompt to accept the value shown in parentheses. All four values are saved
after you enter them, so the next run pre-fills the same defaults and you only need to press ENTER
four times to get back to where you left off.

---

## Step-by-Step: Starting a New Project

### 1. Prepare the target repo

If the repo was cloned from a remote (e.g. Azure DevOps) and you want Claude's commits to stay
local, convert it to a local-only repo first:

```powershell
# Remove existing git history and remote
Remove-Item -Recurse -Force 'C:\Path\To\Repo\.git'

# Re-initialize as a fresh local repo
cd 'C:\Path\To\Repo'
git init
git add .
git commit -m "Initial commit"
```

With no remote configured, `git push` won't do anything — all commits stay on your machine.

### 2. Write your goal

Edit `prompt.txt` (copy from `prompt.txt.example` if starting fresh). Be specific: what feature
needs to be built, what the acceptance criteria are, and any hard constraints (tech stack, naming
conventions, must-not-break list).

### 3. Run the script and enter your settings

```powershell
.\continuous-claude.ps1
```

Enter repo path, worklog path (e.g. `claude-worklog` — created next to the script by default),
and a short project name like `MyFeature`. The project name becomes the branch name and worklog
subfolder, so keep it filesystem-safe.

### 4. Option 1 — Setup

Press **1** and hit ENTER. The script will:

1. Confirm git, Claude CLI, and all prompt template files are present — lists any missing templates
2. Create the worklog, project, and reviews folders if they don't exist yet
3. Create a `.gitignore` in the repo if there isn't one
4. Check out a new branch in the target repo: `continuous-claude/<ProjectName>`

If a stale `.lock` file was left by a crashed previous run, it is cleared automatically.
Run this once per project — you don't need to repeat it on subsequent sessions.

### 5. Option 2 — Discovery

Press **2** and hit ENTER. Here is exactly what happens:

**Step 1 — Shared memory check.** The script looks for a `discovery-memory.md` file built up
from past projects. If found, it compacts that history down to one answer per question (most
recent wins) and passes it to Claude so repeated questions across projects are pre-filled rather
than re-answered from scratch.

**Step 2 — Claude generates the questionnaire.** Claude reads your codebase and `prompt.txt`
goal, then writes a structured `DISCOVERY.md` file in your worklog folder. The format uses
numbered question/answer pairs:

```
Q1. What should be tested — unit, integration, or both?
A1.

Q2. Which external dependencies should be mocked?
A2.
```

This takes a minute or two depending on codebase size. You will see Claude's output scroll past
in the terminal as it works.

**Step 3 — Notepad opens.** Once `DISCOVERY.md` is written, it opens automatically in Notepad.
Fill in each `A` line with your answer. Typical questions cover:

- Testing strategy — unit, integration, or both
- Which dependencies should be mocked vs hit for real
- Acceptance criteria and edge cases to cover
- Whether a new project or solution file needs to be created
- Path to a reference project Claude can use as a pattern guide

**Step 4 — Blank answer validation.** When you save and close Notepad, the script scans for any
`A` lines left empty. If any are found, it lists them and asks whether to re-open — say **Y**
and fill them in. Blank answers reduce the quality of the task plan generated in Option 3.

**Step 5 — Save to shared memory.** After all answers are filled you are asked:

```
Save these answers to shared memory for future projects? (Y/n)
```

Say **Y**. Claude extracts your answers and appends them (dated, by project) to
`_memory\discovery-memory.md`. The next time you run Option 2 on a similar project, those
answers pre-fill automatically — you only need to correct what is different.

### 6. Option 3 — Generate Task Plan

Press **3** and hit ENTER. The script will:

1. Read your completed `DISCOVERY.md`
2. Send your goal and discovery answers to Claude
3. Save the resulting TDD checklist to `TASK_PLAN.md` and print it to the screen

Each task in the plan is tagged with its phase:

| Tag | Meaning |
|-----|---------|
| `[SETUP]` | Infrastructure (project creation, package installs, config) |
| `[NEW-PROJECT]` | A new .csproj / solution must be created — auto-loop pauses for confirmation |
| `[RED]` | Write a failing test that captures the requirement |
| `[GREEN]` | Write the minimum implementation to make the test pass |
| _(no tag)_ | Standard task — implement and verify in one pass |

After Option 3 completes, run **Option T** to review the plan and **Option R** to audit it for
dependency ordering issues before starting iterations.

### 7. Option R — Dependency Review

Press **R** and hit ENTER. The script will:

1. Send the task plan to Claude for analysis
2. Report any forward-reference violations — tasks that assume something exists which hasn't been built yet
3. If violations are found, offer to auto-fix: backs up the original plan, has Claude repair the ordering, then re-runs the review to confirm

Run this after every plan generation and after any manual edits to the plan.

### Ready to run — Option 9

Once Options 1 → 2 → 3 → R are done and the task plan looks right, press **9** to start the
auto-loop. You will be asked how many iterations to run. The script shows a preview of which tasks
will be attempted, asks for confirmation, then runs the full cycle automatically:

```
Build Prompt (4) → Run Claude (5) → Code Review (6) → Commit (8) → next task → repeat
```

You can re-run Option 9 as many times as you like to work through the plan in batches. The
iteration counter and task progress persist between sessions — closing and restarting the script
picks up exactly where it left off.

---

## Running Iterations

### Auto-Loop (recommended)

**Option 9** is the normal way to run. It asks how many iterations to run, shows a preview of
which tasks will be attempted, then executes the full cycle automatically:

```
Build Prompt (4) → Run Claude (5) → Code Review (6) → Commit (8) → repeat
```

The loop handles:
- **Rate limits** — detects the reset time from Claude's output and sleeps until the window clears,
  then retries automatically
- **Review action items** — skips the commit and loops back to fix mode instead
- **Loop detection** — if the same review action items survive three consecutive fix attempts,
  the loop pauses and presents four options: run the break-loop diagnostic, open the review in
  Notepad to override manually, continue anyway, or return to the menu
- **Already-done tasks** — if Claude signals `TASK_ALREADY_COMPLETE`, the task is marked done and
  the loop advances without a commit
- **NEW-PROJECT tasks** — the loop pauses and asks for confirmation before creating new
  project/solution infrastructure

At the end of the batch the remaining task plan is shown. Re-run Option 9 to continue.

### Manual Single Iteration

When you want to inspect each step before moving forward:

1. **Option 4** — Build Prompt (assembles the prompt file for the current task)
2. **Option 5** — Run Claude (executes Claude against the prompt)
3. **Option 7** — Review Changes (optional — inspect the git diff and iteration notes)
4. **Option 6** — Code Review (sends the diff to Claude for a structured review)
5. If action items → go back to **Option 4** (it will switch to FIX mode automatically)
6. If clean → **Option 8** — Commit (commits, marks the task complete, advances the counter)

---

## When Things Get Stuck

### Break-Loop Diagnostic — Option L

Use when the auto-loop has paused due to three consecutive failed fix attempts, or any time
the review keeps generating the same action items despite Claude's attempts to fix them.

Claude acts as an auditor: it reads the review file and the current code, diagnoses why the
loop is stuck (conflicting reviewer guidance, misunderstood action items, regression introduced
by a fix), and either resolves the action items directly or updates the review file to reflect
what was actually fixed.

### Edit the review file manually

If the break-loop diagnostic doesn't resolve it, Option 2 in the loop-detection menu opens the
last review file in Notepad. You can edit or remove the `## Action Items` section to unblock the
commit manually — useful when the reviewer is flagging a known acceptable pattern.

---

## Finishing Up

### Option T — View Task Plan

Shows the full task plan colour-coded by status: gray (done), cyan (SETUP), red (RED phase),
green (GREEN phase), magenta (NEW-PROJECT), yellow (standard pending). Use this to track
progress and confirm the right task is next.

### Option A — Merge into Main

When all tasks are complete, Option A merges the `continuous-claude/<ProjectName>` branch into
`main` with a no-fast-forward merge commit.

---

## Workflow Reference

### The menu

Each time you return to the menu, the header shows the current state of your session:

```
===========================================
 Continuous Claude - Manual Iteration Tool
===========================================
  Project   : testWebAPI_1_0
  Repo      : C:\Repos\continuous-claude\testWebAPI.1
  Worklog   : C:\Repos\continuous-claude\claude-worklog\testWebAPI_1_0
  Iteration : 34   |   Tasks: 13/13 complete
  Discovery : Done   |   Task Plan: Done   |   Audio: ON
-------------------------------------------
```

| Field | What it tells you |
|-------|------------------|
| **Project** | The active project name — also the git branch suffix and worklog subfolder |
| **Repo** | The target repository Claude is working in |
| **Worklog** | Where task plans, notes, and reviews for this project are stored |
| **Iteration** | How many Claude iterations have run, and how many tasks are done vs total |
| **Discovery** | Whether the discovery Q&A has been completed (`Done` / `Not run`) |
| **Task Plan** | Whether a TDD task plan has been generated (`Done` / `Not run`) |
| **Audio** | Whether the completion chime is enabled (`ON` / `OFF`) |

If the last code review has unresolved action items, a warning line appears between the header
and the menu — a reminder not to commit until they are resolved.

### Options

| Key | Option | When to use |
|-----|--------|-------------|
| **1** | Setup & Environment Validation | First time only — validates git, Claude CLI, and prompt templates; creates worklog folders; checks out the `continuous-claude/<ProjectName>` branch |
| **2** | Run Discovery Session | First time, or when starting a significantly different feature — Claude reads the repo and generates a Q&A file you fill in; answers carry into all subsequent prompts |
| **3** | Generate TDD Task Plan | After discovery — Claude converts your answers into a tagged TDD checklist |
| **4** | Build Prompt for Current Task | Before each manual iteration — assembles the full prompt for the current task; auto-selects FIX mode if the last review had action items |
| **5** | Run Claude Iteration | After building the prompt — pipes the prompt to Claude and captures output |
| **6** | Run Code Review | After Claude runs — sends the git diff to Claude for a structured review; flags action items if any |
| **7** | Review File Changes (git) | Optional — shows `git status`, `git diff`, and the current iteration notes so you can inspect what changed before committing ⚠️ *Not yet tested* |
| **8** | Commit & Mark Task Complete | When the review is clean — commits staged changes, marks the current task done in the plan, and advances the iteration counter |
| **9** | Auto-Run Loop | Normal running mode — enter how many iterations to run; the script handles Build → Run → Review → Commit automatically, pausing only when it needs a decision from you |
| **T** | View Task Plan | Any time — shows the full task plan colour-coded by status: gray (done), cyan (SETUP), red (RED), green (GREEN), magenta (NEW-PROJECT), yellow (pending) |
| **R** | Review Task Plan Dependencies | After generating or editing the task plan — audits for forward-reference violations and offers to auto-repair them |
| **L** | Break-Loop Diagnostic | When the auto-loop has paused after three failed fix attempts — Claude acts as auditor to diagnose and resolve the stuck review |
| **B** | Toggle Audio Beep | Any time — enables or disables the two-tone completion chime; setting is saved across sessions |
| **A** | Merge Branch into main | When all tasks are complete — merges the `continuous-claude/<ProjectName>` branch into `main` ⚠️ *Not yet tested* |
| **0** | Exit | Exits the script |

---

## Running Multiple Projects in Parallel

Each project runs in its own PowerShell window. Project isolation is by name — each gets its own:
- Worklog folder and task plan
- Git branch (`continuous-claude/<ProjectName>`)
- Iteration counter
- Window title (set to `Claude Code — <ProjectName>` for taskbar identification)
- Audio chime frequency (derived from a hash of the project name — you can tell which window
  finished by sound alone)

The shared constraint is your Claude account's rate limit. The script handles rate limits
automatically: it parses the reset time from Claude's output and sleeps until the window clears.

---

## Customizing Prompt Templates

All Claude prompts are loaded from the `prompts/` folder. Copy and edit any file to change how
Claude behaves — no script changes needed.

| File | Controls |
|------|---------|
| `discovery-template.md` | Questions Claude asks during the discovery session |
| `task-plan-template.md` | How the TDD task plan is structured |
| `iteration-wrapper.md` | The outer structure of every iteration prompt |
| `iteration-advance.md` | Task + verify instructions for standard tasks |
| `iteration-red.md` | Task + verify instructions for RED phase |
| `iteration-green.md` | Task + verify instructions for GREEN phase |
| `iteration-fix.md` | Task + verify instructions for fix iterations |
| `code-review.md` | Code review checklist |
| `break-loop.md` | Break-loop diagnostic instructions |
| `dependency-review.md` | Task plan dependency audit instructions |
| `dependency-repair.md` | Task plan dependency repair instructions |
| `save-discovery-memory.md` | How discovery answers are saved to shared memory |
| `code-standards-template.md` | Appended to every iteration prompt (optional) |

To adapt for a non-.NET stack, edit `iteration-advance.md`, `iteration-red.md`,
`iteration-green.md`, and `iteration-fix.md` to replace `dotnet build` / `dotnet test`
with your own build and test commands.

---

## Configuration

### appsettings.json

Controls the default paths shown at startup. Paths can be relative (resolved against the script
folder) or absolute.

```json
{
  "DefaultRepoPath": "",
  "DefaultWorklogPath": "claude-worklog",
  "DefaultPromptsPath": "prompts"
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `DefaultRepoPath` | _(empty)_ | Pre-fill the repo path prompt. Leave empty to always prompt. |
| `DefaultWorklogPath` | `claude-worklog` | Where iteration notes, task plans, and reviews are saved. |
| `DefaultPromptsPath` | `prompts` | Folder containing Claude prompt templates. |

After you answer the startup prompts, the values you entered are saved to `settings.json` inside
the worklog. On the next run those saved values take precedence over `appsettings.json`, so you
only need to type the paths once.

---

## Security Notice

This script invokes Claude Code with `--dangerously-skip-permissions` on every call. This flag
gives Claude unrestricted access to read, write, and execute commands in your repository with
no approval prompts. This is required for the automated loop to function without human
intervention on every file change.

**Only point this script at repositories you control and trust.** Review the task plan before
running the auto-loop and inspect commits before pushing to a shared remote.

---

## File Layout

```
continuous-claude.ps1        # Main script
CC.bat                       # Double-click launcher (runs the script via PowerShell)
appsettings.json             # Default paths (relative to this folder)
prompt.txt                   # Your project goal (excluded from git — create from .example)
prompt.txt.example           # Template for creating prompt.txt
prompts/                     # All Claude prompt templates — customize for your stack
  discovery-template.md
  task-plan-template.md
  code-review.md
  iteration-wrapper.md
  iteration-advance.md
  iteration-red.md
  iteration-green.md
  iteration-fix.md
  break-loop.md
  dependency-review.md
  dependency-repair.md
  save-discovery-memory.md
  code-standards-template.md   # Optional — customize or remove
claude-worklog/              # Generated at runtime — excluded from git
  <ProjectName>/
    TASK_PLAN.md
    DISCOVERY.md
    SHARED_TASK_NOTES.md
    prompt.txt               # Built prompt for current iteration
    claude-reviews/
      CODE_REVIEW_iter_001.md
      CODE_REVIEW_iter_002.md
      ...
  _memory/
    settings.json            # Saved startup values (repo, worklog, project name)
    discovery-memory.md      # Accumulated Q&A answers across all past projects
```

## License

MIT
