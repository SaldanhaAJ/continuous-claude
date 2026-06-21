# ================================
# Continuous Claude Manual Runner
# Option B - Menu-based Workflow
# ================================
$ErrorActionPreference = "Stop"

# --- CONFIGURATION DEFAULTS ---
# Seed from appsettings.json alongside the script; relative paths resolve against $PSScriptRoot
$DefaultRepoPath    = ""
$DefaultWorklogPath = Join-Path $PSScriptRoot "worklog"
$DefaultPromptsPath = Join-Path $PSScriptRoot "prompts"

$_appSettingsFile = Join-Path $PSScriptRoot "appsettings.json"
if (Test-Path $_appSettingsFile) {
    try {
        $a = Get-Content $_appSettingsFile -Raw | ConvertFrom-Json
        foreach ($key in @('DefaultRepoPath','DefaultWorklogPath','DefaultPromptsPath')) {
            $val = $a.$key
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $resolved = if ([System.IO.Path]::IsPathRooted($val)) { $val } else { Join-Path $PSScriptRoot $val }
                Set-Variable -Name $key -Value $resolved
            }
        }
    } catch {}
}

$GoalFile = Join-Path $PSScriptRoot "prompt.txt"
if (-Not (Test-Path $GoalFile)) {
    Write-Host "ERROR: prompt.txt not found at $GoalFile"
    exit 1
}
$PrimaryGoal = Get-Content $GoalFile -Raw

# --- BOOTSTRAP: load saved defaults before prompts ---
$_bootstrapSettings = Join-Path $DefaultWorklogPath "_memory\settings.json"
$_savedRepo    = $DefaultRepoPath
$_savedWorklog = $DefaultWorklogPath
$_savedPrompts = $DefaultPromptsPath
$_savedProject = ""
if (Test-Path $_bootstrapSettings) {
    try {
        $s = Get-Content $_bootstrapSettings -Raw | ConvertFrom-Json
        if ($s.RepoPath)     { $_savedRepo    = $s.RepoPath }
        if ($s.WorklogPath)  { $_savedWorklog = $s.WorklogPath }
        if ($s.PromptsPath)  { $_savedPrompts = $s.PromptsPath }
        if ($s.ProjectName)  { $_savedProject = $s.ProjectName }
    } catch {}
}

# --- STARTUP PROMPTS ---
Clear-Host
Write-Host "==========================================="
Write-Host " Continuous Claude - Manual Iteration Tool "
Write-Host "==========================================="
Write-Host ""

$repoInput = Read-Host "Repo path (ENTER for $_savedRepo)"
$RepoPath  = if ([string]::IsNullOrWhiteSpace($repoInput)) { $_savedRepo } else { $repoInput.Trim().Trim('"') }

$worklogInput = Read-Host "Worklog path (ENTER for $_savedWorklog)"
$WorklogPath  = if ([string]::IsNullOrWhiteSpace($worklogInput)) { $_savedWorklog } else { $worklogInput.Trim().Trim('"') }

$promptsInput = Read-Host "Prompts path (ENTER for $_savedPrompts)"
$PromptsPath  = if ([string]::IsNullOrWhiteSpace($promptsInput)) { $_savedPrompts } else { $promptsInput.Trim().Trim('"') }

$projectPrompt = if ($_savedProject) { "Project name (ENTER for $_savedProject)" } else { "Project name (used for worklog folder)" }
$projectInput  = Read-Host $projectPrompt
$ProjectName   = if ([string]::IsNullOrWhiteSpace($projectInput)) { $_savedProject } else { $projectInput.Trim() }
if ([string]::IsNullOrWhiteSpace($ProjectName)) { $ProjectName = "default" }
$ProjectName   = $ProjectName -replace '[^\w\-]', '_'

$MemoryPath          = Join-Path $WorklogPath "_memory"
$DiscoveryMemoryFile = Join-Path $MemoryPath "discovery-memory.md"
$SettingsFile        = Join-Path $MemoryPath "settings.json"

$WorklogPath   = Join-Path $WorklogPath $ProjectName
$NotesFile     = Join-Path $WorklogPath "SHARED_TASK_NOTES.md"
$PromptFile    = Join-Path $WorklogPath "prompt.txt"
$ReviewsPath   = Join-Path $WorklogPath "claude-reviews"
$TaskPlanFile  = Join-Path $WorklogPath "TASK_PLAN.md"
$DiscoveryFile = Join-Path $WorklogPath "DISCOVERY.md"

# Derive iteration number from existing review files so restarts continue where they left off
$existingReviews = Get-ChildItem $ReviewsPath -Filter "CODE_REVIEW_iter_*.md" -ErrorAction SilentlyContinue
$script:IterationNumber = if ($existingReviews) { $existingReviews.Count + 1 } else { 1 }

# Set console window title so taskbar identifies this instance
$Host.UI.RawUI.WindowTitle = "Claude Code - $ProjectName"

# Derive a unique base frequency for this project (220-440 Hz - lower, warmer range)
# A musical fifth above (x1.5) is used as the second note for a pleasant ding-dong chime
$script:BeepFreq = 220 + ([Math]::Abs($ProjectName.GetHashCode()) % 220)

# Tracks consecutive FIX iterations without a successful commit - used for loop detection
$script:ConsecutiveFixCount = 0

# Load persisted settings (beep on/off) - default to enabled
$script:BeepEnabled = $true
if (Test-Path $SettingsFile) {
    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        if ($null -ne $settings.BeepEnabled) { $script:BeepEnabled = [bool]$settings.BeepEnabled }
    } catch { <# malformed settings file - use defaults #> }
}

# ============= FUNCTIONS ==================

function Save-Settings {
    if (-Not (Test-Path $MemoryPath)) { New-Item -ItemType Directory -Path $MemoryPath | Out-Null }
    @{
        BeepEnabled = $script:BeepEnabled
        RepoPath    = $RepoPath
        WorklogPath = (Split-Path $WorklogPath -Parent)
        PromptsPath = $PromptsPath
        ProjectName = $ProjectName
    } | ConvertTo-Json | Set-Content $SettingsFile -Encoding UTF8
}

function Get-PromptTemplate {
    param([string]$FileName, [hashtable]$Vars = @{})
    $path = Join-Path $PromptsPath $FileName
    if (-Not (Test-Path $path)) {
        Write-Host "ERROR: Prompt template not found: $path" -ForegroundColor Red
        throw "Missing prompt template: $FileName"
    }
    $content = Get-Content $path -Raw -Encoding UTF8
    foreach ($key in $Vars.Keys) {
        $content = $content.Replace("{{$key}}", $Vars[$key])
    }
    return $content
}

# Reduce discovery memory noise by extracting the most recent unique answer per question
# across all past project entries, so Claude receives one compact pre-fill block instead
# of every historical entry repeated verbatim.
function Get-CompactMemory {
    param([string]$MemoryFile)

    $raw = Get-Content $MemoryFile -Raw -Encoding UTF8

    # Split into dated project blocks (each starting with ## [date])
    $blocks = [regex]::Split($raw, '(?m)(?=^## \[\d{4}-\d{2}-\d{2}\])')
    $blocks  = @($blocks | Where-Object { $_ -match '## \[\d{4}-\d{2}-\d{2}\]' })

    if ($blocks.Count -eq 0) {
        return "`n`n## ANSWERS FROM PAST PROJECTS (use these to pre-fill where relevant)`n$raw"
    }

    # Walk blocks in order; later entries overwrite earlier ones so most-recent answer wins
    $latestByQ = [ordered]@{}
    foreach ($block in $blocks) {
        $lines = $block -split "`r?`n"
        $currentQ = $null
        foreach ($line in $lines) {
            if ($line -match '^\s*-\s*Q:\s*(.+)$') {
                $currentQ = $matches[1].Trim()
            } elseif ($line -match '^\s*A:\s*(.+)$' -and $currentQ) {
                $answer = $matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($answer)) {
                    $latestByQ[$currentQ] = $answer
                }
                $currentQ = $null
            }
        }
    }

    if ($latestByQ.Count -eq 0) {
        return "`n`n## ANSWERS FROM PAST PROJECTS (use these to pre-fill where relevant)`n$raw"
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("`n`n## ANSWERS FROM PAST PROJECTS (use these to pre-fill where relevant)")
    foreach ($q in $latestByQ.Keys) {
        [void]$sb.AppendLine("- Q: $q")
        [void]$sb.AppendLine("  A: $($latestByQ[$q])")
        [void]$sb.AppendLine("")
    }
    return $sb.ToString()
}

function Toggle-Beep {
    $script:BeepEnabled = -not $script:BeepEnabled
    Save-Settings
    $state = if ($script:BeepEnabled) { "ON" } else { "OFF" }
    Write-Host ""
    Write-Host "  *** Audio beep is now: $state ***" -ForegroundColor Yellow
    Write-Host "  Settings saved to: $SettingsFile"
    Write-Host ""
    if ($script:BeepEnabled) { Send-Notification "Beep enabled" }
    Read-Host "Press ENTER to return to menu"
}

# Send an audio + visual notification identifying this project and step
function Send-Notification {
    param([string]$StepName)

    if ($script:BeepEnabled) {
        # Gentle two-tone chime: low note then a fifth above (1.5x), soft durations
        $high = [int]($script:BeepFreq * 1.5)
        [System.Console]::Beep($script:BeepFreq, 180)
        Start-Sleep -Milliseconds 60
        [System.Console]::Beep($high, 300)
    }

    # Windows balloon notification -- visible even when window is not in focus
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon    = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.ShowBalloonTip(8000, "Claude Code: $ProjectName", $StepName, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        # Balloon notifications not available
    }
}

function Get-CurrentTask {
    if (-Not (Test-Path $TaskPlanFile)) { return $null }
    $lines = Get-Content $TaskPlanFile
    $taskLine = $lines | Where-Object { $_ -match '^\s*- \[ \]' } | Select-Object -First 1
    if ($taskLine) {
        return ($taskLine -replace '^\s*- \[ \]\s*', '').Trim()
    }
    return $null
}

function Get-TaskProgress {
    if (-Not (Test-Path $TaskPlanFile)) { return "No task plan yet" }
    $lines = Get-Content $TaskPlanFile
    $done  = ($lines | Where-Object { $_ -match '^\s*- \[x\]' }).Count
    $todo  = ($lines | Where-Object { $_ -match '^\s*- \[ \]' }).Count
    return "Tasks: $done/$($done + $todo) complete"
}

function Test-IsRedPhase {
    $task = Get-CurrentTask
    if (-Not $task) { return $false }
    return $task -match '\[RED\]'
}

function Test-IsGreenPhase {
    $task = Get-CurrentTask
    if (-Not $task) { return $false }
    return $task -match '\[GREEN\]'
}

function Test-ReviewHasActionItems {
    $lastReview = Get-ChildItem $ReviewsPath -Filter "CODE_REVIEW_iter_*.md" -ErrorAction SilentlyContinue |
                  Sort-Object Name | Select-Object -Last 1
    if (-Not $lastReview) { return $false }
    $content = Get-Content $lastReview.FullName -Raw
    if ($content -match "No action items") { return $false }
    return $content -match "##\s*Action Items"
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================="
    Write-Host " Continuous Claude - Manual Iteration Tool "
    Write-Host "==========================================="
    Write-Host "  Project   : $ProjectName"
    Write-Host "  Repo      : $RepoPath"
    Write-Host "  Worklog   : $WorklogPath"
    Write-Host "  Iteration : $($script:IterationNumber)   |   $(Get-TaskProgress)"
    $currentTask = Get-CurrentTask
    if ($currentTask) {
        $phase = ""
        if ($currentTask -match '\[RED\]')   { $phase = " [RED - write failing test]" }
        if ($currentTask -match '\[GREEN\]') { $phase = " [GREEN - make tests pass]" }
        Write-Host "  Next Task : $currentTask$phase"
    }
    if (Test-ReviewHasActionItems) {
        Write-Host "  *** Review has action items - fix before advancing ***"
    }
    $discoveryStatus = if (Test-Path $DiscoveryFile) { "Done" } else { "Not run" }
    $planStatus      = if (Test-Path $TaskPlanFile)  { "Done" } else { "Not run" }
    $beepStatus      = if ($script:BeepEnabled) { "ON" } else { "OFF" }
    Write-Host "  Discovery : $discoveryStatus   |   Task Plan: $planStatus   |   Audio: $beepStatus"
    Write-Host "-------------------------------------------"
    Write-Host "1. Setup & Environment Validation"
    Write-Host "2. Run Discovery Session"
    Write-Host "3. Generate TDD Task Plan"
    Write-Host "4. Build Prompt for Current Task"
    Write-Host "5. Run Claude Iteration"
    Write-Host "6. Run Code Review"
    Write-Host "7. Review File Changes (git)"
    Write-Host "8. Commit & Mark Task Complete"
    Write-Host "9. Auto-Run Loop"
    Write-Host "T. View Task Plan"
    Write-Host "R. Review Task Plan Dependencies"
    Write-Host "L. Break-Loop Diagnostic (fix stuck review)"
    Write-Host "B. Toggle Audio Beep (currently $beepStatus)"
    Write-Host "A. Merge Branch into main"
    Write-Host "0. Exit"
    Write-Host "==========================================="
}

function Pause-ForUser {
    Write-Host ""
    Read-Host "Press ENTER to continue..." | Out-Null
}

# ---------------------------
# OPTION 1 - SETUP & VALIDATION
# ---------------------------
function Do-Setup {
    Write-Host "`n--- VALIDATING ENVIRONMENT ---`n"

    if (-Not (Test-Path $RepoPath)) { Write-Host "Repository not found at $RepoPath"; return }
    Write-Host "Repository found: $RepoPath"

    if (-Not (Get-Command "git" -ErrorAction SilentlyContinue)) { Write-Host "Git not found"; return }
    Write-Host "Git detected"

    if (-Not (Get-Command "claude" -ErrorAction SilentlyContinue)) { Write-Host "Claude CLI not found"; return }
    Write-Host "Claude CLI detected"

    $requiredTemplates = @(
        "discovery-template.md", "task-plan-template.md", "iteration-wrapper.md",
        "iteration-advance.md", "iteration-red.md", "iteration-green.md", "iteration-fix.md",
        "code-review.md", "break-loop.md", "dependency-review.md", "dependency-repair.md",
        "save-discovery-memory.md"
    )
    $missingTemplates = $requiredTemplates | Where-Object { -Not (Test-Path (Join-Path $PromptsPath $_)) }
    if ($missingTemplates) {
        Write-Host "`nWARNING: Missing prompt templates in $PromptsPath`:" -ForegroundColor Yellow
        $missingTemplates | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    } else {
        Write-Host "Prompt templates: OK ($($requiredTemplates.Count) found in $PromptsPath)"
    }

    foreach ($folder in @($MemoryPath, $WorklogPath, $ReviewsPath)) {
        if (-Not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder | Out-Null
            Write-Host "Created: $folder"
        } else {
            Write-Host "Exists : $folder"
        }
    }

    $gitignorePath = Join-Path $RepoPath ".gitignore"
    if (-Not (Test-Path $gitignorePath)) {
        Write-Host "`n--- Creating .gitignore ---"
        $gitignoreContent = "bin/`nobj/`n*.user`n.vs/`n*.suo`n*.log`nappsettings.Development.json`n"
        $gitignoreContent | Set-Content $gitignorePath -Encoding UTF8
        Write-Host ".gitignore created"
    } else {
        Write-Host ".gitignore exists"
    }

    Set-Location $RepoPath
    Write-Host "`n--- Creating iteration branch ---"
    $branchName = "continuous-claude/$ProjectName"
    $lockFile = Join-Path $RepoPath ".git\refs\heads\continuous-claude\$ProjectName.lock"
    if (Test-Path $lockFile) {
        try { [System.IO.File]::Delete($lockFile); Write-Host "Cleared stale lock file." }
        catch { Write-Host "WARNING: Could not clear lock file at $lockFile" -ForegroundColor Yellow }
    }
    git checkout -B $branchName

    Write-Host "`nSetup complete."
    Send-Notification "Setup complete"
    Pause-ForUser
}

# ---------------------------
# SAVE DISCOVERY ANSWERS TO SHARED MEMORY
# ---------------------------
function Save-DiscoveryMemory {
    if (-Not (Test-Path $DiscoveryFile)) { return }
    if (-Not (Test-Path $MemoryPath)) {
        New-Item -ItemType Directory -Path $MemoryPath | Out-Null
    }

    $savePrompt = Get-PromptTemplate "save-discovery-memory.md" @{
        DISCOVERY_FILE = $DiscoveryFile
        MEMORY_FILE    = $DiscoveryMemoryFile
        DATE           = (Get-Date -Format 'yyyy-MM-dd')
        PROJECT_NAME   = $ProjectName
    }

    Write-Host "Saving discovery answers to shared memory..."
    $savePrompt | claude --print --allowed-tools "Read,Write" --dangerously-skip-permissions | Out-Null
    Write-Host "Saved to: $DiscoveryMemoryFile"
}

# ---------------------------
# GET SAMPLE PROJECT PATH FROM DISCOVERY
# ---------------------------
function Get-SampleProjectPath {
    if (-Not (Test-Path $DiscoveryFile)) { return $null }
    $lines = Get-Content $DiscoveryFile
    $a11 = $lines | Where-Object { $_ -match '^A11\.' } | Select-Object -First 1
    if (-Not $a11) { return $null }
    $val = ($a11 -replace '^A11\.\s*', '').Trim()
    if ([string]::IsNullOrWhiteSpace($val) -or $val -ieq 'none' -or $val -ieq 'n/a') { return $null }

    # Extract just the first Windows path from the answer - handles prose like:
    # "`C:\foo\bar` -- in particular `SomeProject` for patterns"
    $pathMatch = [regex]::Match($val, '[A-Za-z]:\\[^\s`"'']+')
    if ($pathMatch.Success) { return $pathMatch.Value.TrimEnd('\', '.') }

    # Fallback: return cleaned value as-is
    return $val.Trim('`').Trim('"').Trim("'")
}

# ---------------------------
# OPTION 2 - DISCOVERY SESSION
# ---------------------------
function Run-DiscoverySession {
    param([switch]$Silent)

    Write-Host "`n--- DISCOVERY SESSION ---`n"
    Set-Location $RepoPath

    if (-Not (Test-Path $WorklogPath)) {
        New-Item -ItemType Directory -Path $WorklogPath | Out-Null
    }

    $memoryContext = ""
    if (Test-Path $DiscoveryMemoryFile) {
        Write-Host "Found shared memory - will pre-fill answers from past projects..."
        $memoryContext = Get-CompactMemory -MemoryFile $DiscoveryMemoryFile
    } else {
        Write-Host "No shared memory yet - starting fresh."
    }

    $discoveryTemplateFile = Join-Path $PromptsPath "discovery-template.md"
    if (-Not (Test-Path $discoveryTemplateFile)) {
        Write-Host "ERROR: discovery-template.md not found at $discoveryTemplateFile" -ForegroundColor Red
        Write-Host "       Add discovery-template.md alongside continuous-claude.ps1 to continue."
        Pause-ForUser
        return
    }
    $rawTemplate     = Get-Content $discoveryTemplateFile -Raw
    $discoveryPrompt = $rawTemplate.Replace('{{REPO_PATH}}',      $RepoPath)
    $discoveryPrompt = $discoveryPrompt.Replace('{{PROJECT_NAME}}',   $ProjectName)
    $discoveryPrompt = $discoveryPrompt.Replace('{{DISCOVERY_FILE}}', $DiscoveryFile)
    $discoveryPrompt = $discoveryPrompt.Replace('{{PRIMARY_GOAL}}',   $PrimaryGoal)
    $discoveryPrompt = $discoveryPrompt.Replace('{{MEMORY_CONTEXT}}', $memoryContext)

    Write-Host "Asking Claude to generate discovery questions..."
    $discoveryPrompt | claude --print --allowed-tools "Read,Bash,Write" --dangerously-skip-permissions | Out-Null

    if (-Not (Test-Path $DiscoveryFile)) {
        Write-Host "Writing discovery file directly..."
        $out = $discoveryPrompt | claude --print --allowed-tools "Read,Bash" --dangerously-skip-permissions
        $out | Set-Content $DiscoveryFile -Encoding UTF8
    }

    Write-Host "`nDiscovery file saved: $DiscoveryFile"
    Write-Host "Opening for you to fill in answers..."
    Start-Process notepad.exe $DiscoveryFile -Wait

    # Validate that the developer filled in all answer lines
    do {
        $blankAnswers = @(Get-Content $DiscoveryFile | Where-Object { $_ -match '^A\d+\.\s*$' })
        if ($blankAnswers.Count -gt 0) {
            Write-Host ""
            Write-Host "  WARNING: The following answer lines are still blank:" -ForegroundColor Yellow
            $blankAnswers | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
            Write-Host ""
            $reopenChoice = Read-Host "Re-open to fill in blank answers? (Y/n)"
            if ($reopenChoice -ne 'n' -and $reopenChoice -ne 'N') {
                Start-Process notepad.exe $DiscoveryFile -Wait
            } else {
                Write-Host "  Proceeding with blank answers - task plan quality may be reduced." -ForegroundColor DarkYellow
                break
            }
        }
    } while ($blankAnswers.Count -gt 0)

    Write-Host "`nAnswers saved."
    $save = Read-Host "Save these answers to shared memory for future projects? (Y/n)"
    if ($save -ne "n" -and $save -ne "N") {
        Save-DiscoveryMemory
    }

    Write-Host "Run Option 3 to generate the TDD task plan."
    Send-Notification "Discovery complete - review answers then run Option 3"
    if (-Not $Silent) { Pause-ForUser }
}

# ---------------------------
# OPTION 3 - GENERATE TDD TASK PLAN
# ---------------------------
function New-TaskPlan {
    param([switch]$Silent)

    Write-Host "`n--- GENERATING TDD TASK PLAN ---`n"
    Set-Location $RepoPath

    $discoveryContext = "(No discovery session run - proceeding without answers)"
    if (Test-Path $DiscoveryFile) {
        $discoveryContext = Get-Content $DiscoveryFile -Raw
        Write-Host "Including discovery answers from: $DiscoveryFile"
    } else {
        Write-Host "WARNING: No discovery file found. Run Option 2 first for best results."
    }

    $sampleProjectPath = Get-SampleProjectPath
    $sampleSection = ""
    if ($sampleProjectPath -and (Test-Path $sampleProjectPath)) {
        Write-Host "Reference project found: $sampleProjectPath"
        $sampleSection = "`n`n## Reference Project`n" +
"A sample/reference project exists at: $sampleProjectPath`n" +
"Read it to understand the expected patterns, structure, and conventions to follow.`n"
    } elseif ($sampleProjectPath) {
        Write-Host "WARNING: Reference project path from Discovery not found: $sampleProjectPath"
    }

    # Check if Discovery indicates a new project is needed
    $newProjectSection = ""
    if (Test-Path $DiscoveryFile) {
        $discoveryLines = Get-Content $DiscoveryFile
        $a12 = $discoveryLines | Where-Object { $_ -match '^A12\.' } | Select-Object -First 1
        if ($a12) {
            $a12val = ($a12 -replace '^A12\.\s*', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($a12val) -and $a12val -ine 'no' -and $a12val -ine 'n/a') {
                $newProjectSection = "`n`n## New Project Required`n" +
"Discovery indicates a new project/solution is needed: $a12val`n" +
"Tag any tasks that create new project infrastructure with [NEW-PROJECT: <name>].`n" +
"Example: - [ ] 1. [NEW-PROJECT: MyNewApi] Create new ASP.NET Core Web API project ...`n"
            }
        }
    }

    $taskPlanTemplateFile = Join-Path $PromptsPath "task-plan-template.md"
    if (-Not (Test-Path $taskPlanTemplateFile)) {
        Write-Host "ERROR: task-plan-template.md not found at $taskPlanTemplateFile" -ForegroundColor Red
        Write-Host "       Add task-plan-template.md alongside continuous-claude.ps1 to continue."
        Pause-ForUser
        return
    }
    $rawPlanTemplate = Get-Content $taskPlanTemplateFile -Raw
    $planPrompt = $rawPlanTemplate.Replace('{{PRIMARY_GOAL}}',        $PrimaryGoal)
    $planPrompt = $planPrompt.Replace('{{DISCOVERY_CONTEXT}}',   $discoveryContext)
    $planPrompt = $planPrompt.Replace('{{REPO_PATH}}',           $RepoPath)
    $planPrompt = $planPrompt.Replace('{{SAMPLE_SECTION}}',      $sampleSection)
    $planPrompt = $planPrompt.Replace('{{NEW_PROJECT_SECTION}}', $newProjectSection)

    Write-Host "Asking Claude to generate TDD task plan..."
    $plan = $planPrompt | claude --print --allowed-tools "Read,Bash,WebFetch" --dangerously-skip-permissions
    $plan | Set-Content $TaskPlanFile -Encoding UTF8

    Write-Host "`nTask plan saved: $TaskPlanFile"
    Write-Host "`n--- TASK PLAN ---"
    Write-Host $plan
    Send-Notification "Task plan ready - review then run Option 4"

    if (-Not $Silent) { Pause-ForUser }
}

# ---------------------------
# OPTION R - REVIEW TASK PLAN DEPENDENCIES
# ---------------------------
function Review-TaskPlanDependencies {
    Write-Host "`n--- REVIEWING TASK PLAN FOR DEPENDENCY VIOLATIONS ---`n"

    if (-Not (Test-Path $TaskPlanFile)) {
        Write-Host "No task plan found. Run Option 3 first."
        Pause-ForUser
        return
    }

    $taskPlanContent = Get-Content $TaskPlanFile -Raw

    $reviewPrompt = Get-PromptTemplate "dependency-review.md" @{
        REPO_PATH = $RepoPath
        TASK_PLAN = $taskPlanContent
    }

    $outputFile = Join-Path $WorklogPath "TASK_PLAN_DEPENDENCY_REVIEW.md"

    Write-Host "Sending task plan to Claude for dependency review..."
    $review = $reviewPrompt | claude --print --allowed-tools "Read,Bash" --dangerously-skip-permissions
    $review | Set-Content $outputFile -Encoding UTF8

    Write-Host "`nReview saved: $outputFile"
    Write-Host "`n--- DEPENDENCY REVIEW RESULTS ---"
    Write-Host $review

    if ($review -match "ISSUE") {
        Write-Host "`n*** Dependency issues found. Fix the task plan before running iterations. ***" -ForegroundColor Red
        Send-Notification "Task plan has dependency issues - review before running"
        Write-Host ""
        $fix = Read-Host "Auto-fix dependency issues now? (Y/n)"
        if ($fix -ne "n" -and $fix -ne "N") {
            Repair-TaskPlanDependencies
            return
        }
    } else {
        Write-Host "`n*** No dependency violations found. Task plan is clean. ***" -ForegroundColor Green
        Send-Notification "Task plan dependency review: PASSED"
    }

    Pause-ForUser
}

# ---------------------------
# OPTION F - REPAIR TASK PLAN DEPENDENCIES
# ---------------------------
function Repair-TaskPlanDependencies {
    Write-Host "`n--- REPAIRING TASK PLAN DEPENDENCY VIOLATIONS ---`n"

    if (-Not (Test-Path $TaskPlanFile)) {
        Write-Host "No task plan found. Run Option 3 first."
        Pause-ForUser
        return
    }

    $reviewFile = Join-Path $WorklogPath "TASK_PLAN_DEPENDENCY_REVIEW.md"
    if (-Not (Test-Path $reviewFile)) {
        Write-Host "No dependency review found. Run Option R first."
        Pause-ForUser
        return
    }

    $taskPlanContent = Get-Content $TaskPlanFile -Raw
    $reviewContent   = Get-Content $reviewFile -Raw

    $repairPrompt = Get-PromptTemplate "dependency-repair.md" @{
        REVIEW_CONTENT = $reviewContent
        TASK_PLAN      = $taskPlanContent
    }

    Write-Host "Sending task plan + review to Claude for repair..."
    $fixed = $repairPrompt | claude --print --allowed-tools "Read" --dangerously-skip-permissions

    # Back up the original before overwriting
    $backupFile = Join-Path $WorklogPath "TASK_PLAN_pre_repair.md"
    Copy-Item $TaskPlanFile $backupFile -Force
    Write-Host "Original backed up to: $backupFile"

    $fixed | Set-Content $TaskPlanFile -Encoding UTF8
    Write-Host "Repaired plan saved to: $TaskPlanFile"
    Write-Host "`n--- REPAIRED PLAN ---"
    Write-Host $fixed

    Write-Host "`nRe-running dependency review to verify fixes..."
    Review-TaskPlanDependencies
}

# ---------------------------
# SAVE VERSIONED NOTES SNAPSHOT
# ---------------------------
function Save-VersionedNotes {
    if (Test-Path $NotesFile) {
        $dest = Join-Path $WorklogPath ("SHARED_TASK_NOTES_iter_{0:D3}.md" -f $script:IterationNumber)
        Copy-Item $NotesFile $dest -Force
        Write-Host "Notes snapshot saved: $dest"
    }
}

# ---------------------------
# OPTION 4 - BUILD PROMPT
# ---------------------------
function Build-Prompt {
    param([switch]$Silent)

    Save-VersionedNotes

    $fixingReview = Test-ReviewHasActionItems
    $currentTask  = Get-CurrentTask
    $isRed        = Test-IsRedPhase
    $isGreen      = Test-IsGreenPhase

    if (-Not $currentTask -and -Not $fixingReview) {
        Write-Host "`nNo task plan found or all tasks complete. Run Option 3 first."
        if (-Not $Silent) { Pause-ForUser }
        return
    }

    Write-Host "`n--- BUILDING PROMPT (Iteration $($script:IterationNumber)) ---`n"

    $previousNotes = "(No notes from previous iteration)"
    if (Test-Path $NotesFile) { $previousNotes = Get-Content $NotesFile -Raw }

    $reviewFeedback = "(No code review yet)"
    $lastReview = Get-ChildItem $ReviewsPath -Filter "CODE_REVIEW_iter_*.md" -ErrorAction SilentlyContinue |
                  Sort-Object Name | Select-Object -Last 1
    if ($lastReview) {
        Write-Host "Including code review: $($lastReview.Name)"
        $reviewFeedback = Get-Content $lastReview.FullName -Raw
    }

    $taskPlanContent = ""
    if (Test-Path $TaskPlanFile) { $taskPlanContent = Get-Content $TaskPlanFile -Raw }

    # Select mode template and log what we're doing
    if ($fixingReview) {
        Write-Host "Mode: FIX REVIEW ISSUES`n"
        $modeFile = "iteration-fix.md"
    } elseif ($isRed) {
        Write-Host "Mode: RED phase -- write failing test`n"
        Write-Host "Task: $currentTask`n"
        $modeFile = "iteration-red.md"
    } elseif ($isGreen) {
        Write-Host "Mode: GREEN phase -- implement to pass tests`n"
        Write-Host "Task: $currentTask`n"
        $modeFile = "iteration-green.md"
    } else {
        Write-Host "Mode: ADVANCE TO NEXT TASK`n"
        Write-Host "Task: $currentTask`n"
        $modeFile = "iteration-advance.md"
    }

    # Load the mode file and split on <!-- VERIFY --> to get task and verify sections
    $modeContent = Get-PromptTemplate $modeFile @{
        CURRENT_TASK = $currentTask
        NOTES_FILE   = $NotesFile
    }
    $modeParts    = $modeContent -split '<!--\s*VERIFY\s*-->', 2
    $taskSection   = $modeParts[0].Trim()
    $verifySection = if ($modeParts.Count -gt 1) { $modeParts[1].Trim() } else { "" }

    # Inject sample project context if one is configured
    $sampleContext = ""
    $samplePath = Get-SampleProjectPath
    if ($samplePath -and (Test-Path $samplePath)) {
        $sampleContext = "`n`n## REFERENCE PROJECT`n" +
"A reference/sample project is available at: $samplePath`n" +
"Read it as needed to follow established patterns, naming conventions, and structure.`n"
    }

    # Load coding standards from prompts folder
    $codingStandards = ""
    $codeStandardsFile = Join-Path $PromptsPath "code-standards-template.md"
    if (Test-Path $codeStandardsFile) {
        $codingStandards = "`n`n" + (Get-Content $codeStandardsFile -Raw -Encoding UTF8)
    }

    $promptContent = Get-PromptTemplate "iteration-wrapper.md" @{
        ITERATION       = "$($script:IterationNumber)"
        NOTES_FILE      = $NotesFile
        PRIMARY_GOAL    = $PrimaryGoal
        SAMPLE_CONTEXT  = $sampleContext
        TASK_PLAN       = $taskPlanContent
        TASK_SECTION    = $taskSection
        PREVIOUS_NOTES  = $previousNotes
        REVIEW_FEEDBACK = $reviewFeedback
        VERIFY_SECTION  = $verifySection
        CODING_STANDARDS = $codingStandards
    }

    $promptContent | Set-Content $PromptFile -Encoding UTF8
    Write-Host "Prompt saved to $PromptFile"

    if (-Not $Silent) { Pause-ForUser }
}

# ---------------------------
# RATE LIMIT HELPERS
# ---------------------------

# Map IANA timezone names to Windows timezone IDs
$script:IanaToWindows = @{
    'America/Chicago'     = 'Central Standard Time'
    'America/New_York'    = 'Eastern Standard Time'
    'America/Denver'      = 'Mountain Standard Time'
    'America/Los_Angeles' = 'Pacific Standard Time'
    'America/Phoenix'     = 'US Mountain Standard Time'
    'America/Anchorage'   = 'Alaskan Standard Time'
    'Pacific/Honolulu'    = 'Hawaiian Standard Time'
    'UTC'                 = 'UTC'
}

function Get-RateLimitResumeTime {
    param([string]$Message)

    # Match "resets 5pm" or "resets 5:30pm" with optional timezone e.g. "(America/Chicago)"
    $m = [regex]::Match($Message, 'resets\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm))\s*(?:\(([^)]+)\))?', 'IgnoreCase')
    if (-not $m.Success) { return $null }

    $timeStr  = $m.Groups[1].Value.Trim()
    $ianaName = $m.Groups[2].Value.Trim()

    # Resolve timezone - fall back to local if unknown
    $tz = [System.TimeZoneInfo]::Local
    if ($ianaName -and $script:IanaToWindows.ContainsKey($ianaName)) {
        try { $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($script:IanaToWindows[$ianaName]) } catch { }
    }

    # Parse the reset time
    $parsed = $null
    if (-not [datetime]::TryParse($timeStr, [ref]$parsed)) { return $null }

    # Build reset datetime in the target timezone
    $nowUtc   = [DateTime]::UtcNow
    $nowInTz  = [System.TimeZoneInfo]::ConvertTimeFromUtc($nowUtc, $tz)
    $resetInTz = [DateTime]::new($nowInTz.Year, $nowInTz.Month, $nowInTz.Day, $parsed.Hour, $parsed.Minute, 0)

    # If already past that time today, roll to tomorrow
    if ($resetInTz -le $nowInTz) { $resetInTz = $resetInTz.AddDays(1) }

    # 2-minute buffer so the limit is fully cleared
    $resetInTz = $resetInTz.AddMinutes(2)

    # Convert back to local time for display and sleeping
    $resetUtc   = [System.TimeZoneInfo]::ConvertTimeToUtc($resetInTz, $tz)
    $resetLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($resetUtc, [System.TimeZoneInfo]::Local)
    return $resetLocal
}

function Wait-ForRateLimit {
    param([string]$LimitMessage)

    Write-Host ""
    Write-Host "  *** CLAUDE RATE LIMIT HIT ***" -ForegroundColor Red
    Write-Host "  $LimitMessage" -ForegroundColor Yellow
    Write-Host ""

    $resumeAt = Get-RateLimitResumeTime -Message $LimitMessage
    if (-not $resumeAt) {
        Write-Host "  Could not parse reset time - defaulting to 60-minute wait." -ForegroundColor Yellow
        $resumeAt = (Get-Date).AddMinutes(60)
    }

    Write-Host "  Will resume at: $($resumeAt.ToString('ddd MMM dd, h:mm tt'))" -ForegroundColor Cyan
    Write-Host ""

    while ((Get-Date) -lt $resumeAt) {
        $remaining = $resumeAt - (Get-Date)
        $mins = [int]$remaining.TotalMinutes
        $secs = $remaining.Seconds
        Write-Host "  Waiting for rate limit to clear... $mins min $secs sec remaining" -ForegroundColor DarkYellow
        Start-Sleep -Seconds 30
    }

    Write-Host ""
    Write-Host "  Rate limit cleared - resuming..." -ForegroundColor Green
    Send-Notification "Rate limit cleared - resuming iteration $($script:IterationNumber)"
    Write-Host ""
}

# ---------------------------
# OPTION 5 - RUN CLAUDE
# ---------------------------
function Run-Claude {
    param([switch]$Silent)

    Write-Host "`n--- RUNNING CLAUDE (Iteration $($script:IterationNumber)) ---`n"
    Set-Location $RepoPath

    if (-Not (Test-Path $PromptFile)) {
        Write-Host "prompt.txt not found. Run Option 4 first."
        return $null
    }

    $output = Get-Content $PromptFile -Raw | claude --print --allowed-tools "Bash,Read,Write,Edit,WebFetch" --dangerously-skip-permissions

    # Auto-retry once if we hit the rate limit
    if ($output -match "hit your limit") {
        $limitLine = ($output -split "`n" | Where-Object { $_ -match "hit your limit" } | Select-Object -First 1)
        Wait-ForRateLimit -LimitMessage $limitLine.Trim()
        Write-Host "--- RETRYING CLAUDE (Iteration $($script:IterationNumber)) ---`n"
        $output = Get-Content $PromptFile -Raw | claude --print --allowed-tools "Bash,Read,Write,Edit,WebFetch" --dangerously-skip-permissions
    }

    Write-Host $output
    if ($output -match "TASK_ALREADY_COMPLETE") {
        Write-Host "`n*** Task already complete. Run Option 8 to mark it done and advance. ***"
        Send-Notification "Iter $($script:IterationNumber): task already done - commit to advance"
    } elseif ($output -match "hit your limit") {
        Write-Host "`n*** Rate limit still active after wait. Stopping. ***" -ForegroundColor Red
        Send-Notification "Rate limit still active - manual restart needed"
    } else {
        Write-Host "`nClaude iteration complete."
        Send-Notification "Iter $($script:IterationNumber) complete - run Code Review (Option 6)"
    }

    if (-Not $Silent) { Pause-ForUser }
    return $output
}

# ---------------------------
# OPTION 6 - CODE REVIEW
# ---------------------------
function Run-CodeReview {
    param([switch]$Silent)

    Write-Host "`n--- RUNNING CODE REVIEW (Iteration $($script:IterationNumber)) ---`n"
    Set-Location $RepoPath

    $reviewFile = Join-Path $ReviewsPath ("CODE_REVIEW_iter_{0:D3}.md" -f $script:IterationNumber)

    try { git add . 2>&1 | Out-Null } catch { <# suppress git line-ending warnings #> }
    $diff = git diff --cached 2>&1
    if ([string]::IsNullOrWhiteSpace($diff)) { $diff = "(No staged changes detected)" }

    $currentTask = Get-CurrentTask
    $phase = "standard"
    if ($currentTask -match '\[RED\]')   { $phase = "RED (write failing test)" }
    if ($currentTask -match '\[GREEN\]') { $phase = "GREEN (implement to pass tests)" }
    if ($currentTask -match '\[SETUP\]') { $phase = "SETUP" }
    if (-Not $currentTask) { $currentTask = "(fix iteration)" }

    $reviewPrompt = Get-PromptTemplate "code-review.md" @{
        ITERATION    = "$($script:IterationNumber)"
        PHASE        = $phase
        CURRENT_TASK = $currentTask
        PRIMARY_GOAL = $PrimaryGoal
        DIFF         = $diff
    }

    Write-Host "Sending diff to Claude for review..."
    $review = $reviewPrompt | claude --print --allowed-tools "Read" --dangerously-skip-permissions
    $review | Set-Content $reviewFile -Encoding UTF8

    Write-Host "`nCode review saved: $reviewFile"
    Write-Host "`n--- REVIEW ---"
    Write-Host $review

    if (Test-ReviewHasActionItems) {
        Write-Host "`n*** Action items found. Run Option 4 to build a fix prompt. ***"
        Send-Notification "Iter $($script:IterationNumber) review: ACTION ITEMS found - check review"
    } else {
        Write-Host "`n*** No action items. Ready to commit (Option 8). ***"
        Send-Notification "Iter $($script:IterationNumber) review: PASSED - ready to commit"
    }

    if (-Not $Silent) { Pause-ForUser }
}

# ---------------------------
# OPTION 7 - REVIEW GIT CHANGES
# ---------------------------
function Review-Changes {
    Write-Host "`n--- REVIEWING CHANGES ---`n"
    Set-Location $RepoPath

    git status
    Write-Host "`n--- Git Diff ---`n"
    git diff

    if (Test-Path $NotesFile) {
        Write-Host "`n--- SHARED_TASK_NOTES.md ---`n"
        Get-Content $NotesFile
    } else {
        Write-Host "`n(No notes file yet.)"
    }

    Pause-ForUser
}

# ---------------------------
# OPTION 8 - COMMIT & MARK TASK COMPLETE
# ---------------------------
function Commit-Changes {
    param([string]$AutoMessage = "")

    Write-Host "`n--- COMMITTING CHANGES ---`n"
    Set-Location $RepoPath

    if (Test-ReviewHasActionItems -and [string]::IsNullOrWhiteSpace($AutoMessage)) {
        Write-Host "WARNING: The last code review has unresolved action items."
        $confirm = Read-Host "Commit anyway? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Commit cancelled. Run Option 4 to build a fix prompt."
            Pause-ForUser
            return
        }
    }

    $currentTask  = Get-CurrentTask
    $fixingReview = Test-ReviewHasActionItems
    $isRed        = Test-IsRedPhase
    $isGreen      = Test-IsGreenPhase

    try { git add . 2>&1 | Out-Null } catch { <# suppress git line-ending warnings #> }
    if ([string]::IsNullOrWhiteSpace($AutoMessage)) {
        $defaultMsg = if ($fixingReview) {
            "Claude iter $($script:IterationNumber): fix review issues"
        } elseif ($isRed) {
            "Claude iter $($script:IterationNumber): [RED] $($currentTask -replace '^\[RED\]\s*','')"
        } elseif ($isGreen) {
            "Claude iter $($script:IterationNumber): [GREEN] $($currentTask -replace '^\[GREEN\]\s*','')"
        } elseif ($currentTask) {
            "Claude iter $($script:IterationNumber): $currentTask"
        } else {
            "Claude iteration $($script:IterationNumber)"
        }
        Write-Host "Suggested: $defaultMsg"
        $msg = Read-Host "Enter commit message (or ENTER to accept)"
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $defaultMsg }
    } else {
        $msg = $AutoMessage
        Write-Host "Auto-committing: $msg"
    }

    # Write message to a temp file to avoid PowerShell mangling special characters
    # (backticks, quotes, brackets in task descriptions break git commit -m)
    $msgFile = Join-Path $env:TEMP "claude_commit_msg.txt"
    $msg | Set-Content $msgFile -Encoding UTF8
    $result = git commit -F $msgFile 2>&1
    Remove-Item $msgFile -ErrorAction SilentlyContinue
    Write-Host $result

    if (-Not $fixingReview -and $currentTask -and (Test-Path $TaskPlanFile)) {
        $content = Get-Content $TaskPlanFile -Raw
        $updated = ([regex]'- \[ \]').Replace($content, '- [x]', 1)
        $updated | Set-Content $TaskPlanFile -Encoding UTF8
        Write-Host "Task marked complete in TASK_PLAN.md"
    }

    $script:IterationNumber++
    $script:ConsecutiveFixCount = 0
    Write-Host "`nMoving to iteration $($script:IterationNumber)."

    $next = Get-CurrentTask
    if ($next) {
        $nextPhase = ""
        if ($next -match '\[RED\]')   { $nextPhase = " [RED]" }
        if ($next -match '\[GREEN\]') { $nextPhase = " [GREEN]" }
        Write-Host "Next task$nextPhase`: $next"
    } else {
        Write-Host "All tasks complete!"
    }

    $nextTask = Get-CurrentTask
    $nextLabel = if ($nextTask) { $nextTask } else { "all tasks complete!" }
    Send-Notification "Iter $($script:IterationNumber - 1) committed - next: $nextLabel"

    if (-Not [string]::IsNullOrWhiteSpace($AutoMessage)) { return }
    Pause-ForUser
}

# ---------------------------
# SHOW TASK PLAN
# ---------------------------
function Show-TaskPlan {
    param([int]$HighlightNext = 0)

    if (-Not (Test-Path $TaskPlanFile)) {
        Write-Host "`n(No task plan found - run Option 3 first)"
        return
    }

    $lines = Get-Content $TaskPlanFile
    Write-Host ""
    foreach ($line in $lines) {
        if ($line -match '^\s*- \[x\]') {
            # Completed - dim with a tick
            Write-Host "  $line" -ForegroundColor DarkGray
        } elseif ($line -match '^\s*- \[ \]') {
            # Pending - colour by phase
            if ($line -match '\[RED\]')              { Write-Host "  $line" -ForegroundColor Red }
            elseif ($line -match '\[GREEN\]')        { Write-Host "  $line" -ForegroundColor Green }
            elseif ($line -match '\[SETUP\]')        { Write-Host "  $line" -ForegroundColor Cyan }
            elseif ($line -match '\[NEW-PROJECT')    { Write-Host "  $line" -ForegroundColor Magenta }
            else                                     { Write-Host "  $line" -ForegroundColor Yellow }
        } else {
            Write-Host $line
        }
    }

    if ($HighlightNext -gt 0) {
        $pending = $lines | Where-Object { $_ -match '^\s*- \[ \]' }
        $batch   = $pending | Select-Object -First $HighlightNext
        Write-Host "`n--- Next $HighlightNext task(s) that will run ---" -ForegroundColor White
        foreach ($t in $batch) {
            Write-Host "  >> $t" -ForegroundColor White
        }
    }
    Write-Host ""
}

# ---------------------------
# OPTION L - BREAK LOOP DIAGNOSTIC
# ---------------------------
function Invoke-BreakLoopPrompt {
    Write-Host "`n--- BREAK-LOOP DIAGNOSTIC ---`n"

    $lastReview = Get-ChildItem $ReviewsPath -Filter "CODE_REVIEW_iter_*.md" -ErrorAction SilentlyContinue |
                  Sort-Object Name | Select-Object -Last 1
    if (-Not $lastReview) {
        Write-Host "No review file found. Nothing to diagnose."
        Pause-ForUser
        return
    }

    $breakPrompt = Get-PromptTemplate "break-loop.md" @{
        CONSECUTIVE_FIX_COUNT = "$($script:ConsecutiveFixCount)"
        REVIEW_FILE           = $lastReview.FullName
        NOTES_FILE            = $NotesFile
        REPO_PATH             = $RepoPath
    }

    Write-Host "Sending break-loop diagnostic to Claude..."
    $output = $breakPrompt | claude --print --allowed-tools "Bash,Read,Write,Edit" --dangerously-skip-permissions
    Write-Host $output

    if (Test-ReviewHasActionItems) {
        Write-Host "`n*** Diagnostic did not clear all action items. Open the review manually (Option 2 below). ***" -ForegroundColor Red
        Send-Notification "Break-loop diagnostic incomplete - manual review needed"
    } else {
        $script:ConsecutiveFixCount = 0
        Write-Host "`n*** Review cleared. Ready to commit (Option 8). ***" -ForegroundColor Green
        Send-Notification "Break-loop resolved - ready to commit"
    }

    Pause-ForUser
}

# ---------------------------
# OPTION 9 - AUTO-RUN LOOP
# ---------------------------
function Run-AutoLoop {
    Write-Host "`n--- AUTO LOOP SETUP ---`n"

    if (-Not (Test-Path $TaskPlanFile)) {
        Write-Host "No task plan found. Run Option 3 first."
        Pause-ForUser
        return
    }

    # Show the task plan so user knows what they are about to run
    Write-Host "=== CURRENT TASK PLAN ===" -ForegroundColor White
    Show-TaskPlan
    Write-Host "(Gray = done, Cyan = SETUP, Red = RED phase, Green = GREEN phase, Magenta = NEW-PROJECT)`n"

    $maxIterations = Read-Host "How many iterations to run before returning to menu (e.g. 3)"
    $maxInt = [int]$maxIterations

    # Preview the tasks that will be attempted
    Show-TaskPlan -HighlightNext $maxInt

    $confirm = Read-Host "Start auto-loop for $maxInt iteration(s)? (Y/n)"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Write-Host "Cancelled."
        Pause-ForUser
        return
    }

    $completed = $false
    $startIter = $script:IterationNumber

    while (($script:IterationNumber - $startIter) -lt $maxInt) {
        $currentTask = Get-CurrentTask
        $fixing      = Test-ReviewHasActionItems

        if (-Not $currentTask -and -Not $fixing) {
            Write-Host "`nAll tasks complete. Stopping loop."
            $completed = $true
            break
        }

        $phase = ""
        if ($currentTask -match '\[RED\]')           { $phase = "[RED] " }
        if ($currentTask -match '\[GREEN\]')         { $phase = "[GREEN] " }
        if ($fixing)                                 { $phase = "[FIX] " }
        if ($currentTask -match '\[NEW-PROJECT')     { $phase = "[NEW-PROJECT] " }

        Write-Host "`n`n=========================================="
        Write-Host "  ITERATION $($script:IterationNumber) -- $phase$currentTask"
        Write-Host "==========================================`n"

        # Pause auto-loop when a new project/solution needs to be created
        # so the user can confirm the project name and location first
        if ($currentTask -match '\[NEW-PROJECT') {
            Write-Host "*** NEW PROJECT task detected. This task requires creating a new project/solution. ***" -ForegroundColor Yellow
            Write-Host "Task: $currentTask" -ForegroundColor Yellow
            Write-Host ""
            $proceed = Read-Host "Proceed with this task? (Y/n)"
            if ($proceed -eq "n" -or $proceed -eq "N") {
                Write-Host "Auto-loop paused by user. Returning to menu."
                break
            }
        }

        Build-Prompt -Silent
        $output = Run-Claude -Silent

        # Rate limit still active after auto-wait - stop loop cleanly
        if ($output -match "hit your limit") {
            Write-Host "`n*** Rate limit still active. Auto-loop stopped at iteration $($script:IterationNumber). ***" -ForegroundColor Red
            Write-Host "Re-run Option 9 to continue from here." -ForegroundColor Yellow
            break
        }

        # Task was already done from a previous iteration - skip review and commit
        if ($output -match "TASK_ALREADY_COMPLETE") {
            Write-Host "`n*** Task already complete - marking done and advancing. ***"
            if ($currentTask -and (Test-Path $TaskPlanFile)) {
                $content = Get-Content $TaskPlanFile -Raw
                $updated = ([regex]'- \[ \]').Replace($content, '- [x]', 1)
                $updated | Set-Content $TaskPlanFile -Encoding UTF8
            }
            Send-Notification "Iter $($script:IterationNumber): task already done - skipped"
            $script:IterationNumber++
        } else {
            Run-CodeReview -Silent

            # Re-check action items AFTER the review runs (not before)
            if (Test-ReviewHasActionItems) {
                $script:ConsecutiveFixCount++
                Write-Host "`n*** Review has action items - skipping commit. Fix attempt $($script:ConsecutiveFixCount). ***"

                # Loop detection - pause after 3 consecutive failed fix attempts
                if ($script:ConsecutiveFixCount -ge 3) {
                    Write-Host ""
                    Write-Host "  *** LOOP DETECTED: $($script:ConsecutiveFixCount) fix attempts without clearing the review. ***" -ForegroundColor Red
                    Write-Host "  Claude may be disagreeing with the reviewer or misunderstanding the action items." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "  1. Run break-loop diagnostic (Claude as auditor - recommended)" -ForegroundColor Cyan
                    Write-Host "  2. Open review file in Notepad to edit manually" -ForegroundColor Cyan
                    Write-Host "  3. Continue auto-loop anyway" -ForegroundColor Cyan
                    Write-Host "  4. Return to menu" -ForegroundColor Cyan
                    Write-Host ""
                    $loopChoice = Read-Host "Select"
                    $stopLoop = $false
                    switch ($loopChoice) {
                        "1" {
                            Invoke-BreakLoopPrompt
                        }
                        "2" {
                            $lastReview = Get-ChildItem $ReviewsPath -Filter "CODE_REVIEW_iter_*.md" -ErrorAction SilentlyContinue |
                                          Sort-Object Name | Select-Object -Last 1
                            if ($lastReview) {
                                Write-Host "Opening review file - edit the '## Action Items' section to resolve or override items."
                                Start-Process notepad.exe $lastReview.FullName -Wait
                                Write-Host "Review file saved."
                            }
                        }
                        "3" { Write-Host "Continuing auto-loop..." }
                        "4" { $stopLoop = $true }
                        default { Write-Host "Continuing auto-loop..." }
                    }
                    if ($stopLoop) {
                        Write-Host "Returning to menu."
                        break
                    }
                }

                Send-Notification "Iter $($script:IterationNumber): review needs fixes - returning to loop"
                $script:IterationNumber++
            } else {
                $autoMsg = if ($fixing) {
                    "Claude iter $($script:IterationNumber): fix review issues"
                } else {
                    "Claude iter $($script:IterationNumber): $phase$currentTask"
                }
                Commit-Changes -AutoMessage $autoMsg
            }
        }

        if ($output -match "CONTINUOUS_CLAUDE_PROJECT_COMPLETE") {
            Write-Host "`n*** Project marked complete by Claude. Stopping loop. ***"
            $completed = $true
            break
        }
    }

    if ($completed) {
        Write-Host "`nAll tasks complete!"
        Send-Notification "All tasks complete!"
    } else {
        Write-Host "`nBatch of $maxInt iteration(s) done. Returning to menu."
        Send-Notification "Auto-loop batch done - $($script:IterationNumber - $startIter) iterations ran"
    }
    Write-Host "`nIteration: $($script:IterationNumber) | $(Get-TaskProgress)"
    Write-Host "`nRemaining tasks:"
    Show-TaskPlan
    Pause-ForUser
}

# ---------------------------
# OPTION A - MERGE BRANCH
# ---------------------------
function Merge-Branch {
    Write-Host "`n--- MERGING INTO MAIN ---`n"
    Set-Location $RepoPath

    git checkout main
    git merge --no-ff "continuous-claude/$ProjectName" -m "Merge Claude TDD iteration"

    Write-Host "`nMerge complete."
    Pause-ForUser
}

# Persist startup values so next run pre-fills repo, worklog, and project
Save-Settings

# ============================
# MAIN LOOP
# ============================
do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Do-Setup }
        "2" { Run-DiscoverySession }
        "3" { New-TaskPlan }
        "4" { Build-Prompt }
        "5" { Run-Claude }
        "6" { Run-CodeReview }
        "7" { Review-Changes }
        "8" { Commit-Changes }
        "9" { Run-AutoLoop }
        "T" { Show-TaskPlan; Pause-ForUser }
        "R" { Review-TaskPlanDependencies }
        "L" { Invoke-BreakLoopPrompt }
        "B" { Toggle-Beep }
        "A" { Merge-Branch }
        "0" { break }
        default { Write-Host "Invalid choice"; Pause-ForUser }
    }

} while ($choice -ne "0")

Write-Host "Exiting..."
