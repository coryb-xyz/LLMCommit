#region Script-Level Helper Functions (for New-LLMCommitMessage)

function script:Test-FileIsPlainText {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    try {
        # Attempt to read the file as UTF-8 and check for control characters
        $content = Get-Content -Path $FilePath -Encoding UTF8 -ErrorAction Stop
        # Basic check for control characters (ASCII 0-8, 11-12, 14-31) - may need refinement
        if ($content -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
            return $false
        }
        return $true # Assume plain text if no control characters found (for now)

    }
    catch {
        # If UTF-8 reading fails, assume not plain text (e.g., binary file)
        return $false
    }
}

function script:Get-FileChangeSummary {
    param(
        [Parameter(Mandatory = $false)]  # Change from Mandatory to optional
        [string[]]$StagedFiles = @(), # Provide default empty array
        [Parameter(Mandatory = $false)]  # Change from Mandatory to optional
        [string[]]$UnstagedFiles = @()  # Provide default empty array
    )

    $allFiles = @($StagedFiles) + @($UnstagedFiles) | Select-Object -Unique

    # Group binary files by directory and extension
    $binaryFiles = $allFiles | Where-Object {
        $fullpath = Resolve-Path $_

        !(Test-FileIsPlainText $fullpath)
    } | Group-Object {
        [System.IO.Path]::GetDirectoryName($_)
    }

    $binarySummary = foreach ($group in $binaryFiles) {
        $exts = $group.Group | ForEach-Object {
            [System.IO.Path]::GetExtension($_)
        } | Select-Object -Unique

        foreach ($ext in $exts) {
            $count = ($group.Group | Where-Object {
                    [System.IO.Path]::GetExtension($_) -eq $ext
                }).Count

            @{
                Directory = $group.Name
                Extension = $ext
                Count     = $count
                Action    = if ($group.Group[0] -in $StagedFiles) { "Added" } else { "Modified" }
            }
        }
    }

    # Find text files that can be diffed
    $textFiles = $allFiles | Where-Object {
        $fullpath = Resolve-Path $_
        Test-FileIsPlainText $fullpath
    }

    return @{
        BinaryChanges = $binarySummary
        TextFiles     = $textFiles
    }
}

function script:Get-FileChanges {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [bool]$IsStaged
    )
    Write-Verbose "Entering Get-FileChanges for '$FilePath', Staged: $($IsStaged)"
    try {
        if ($IsStaged) {
            $diff = git diff --cached $FilePath | Out-String -NoNewline  # Pipe to Out-String to ensure string output
        }
        else {
            $diff = git diff $FilePath | Out-String -NoNewline # Pipe to Out-String to ensure string output
        }
        $diff = $diff.Trim() # Trim whitespace to clean up

        if ($diff) {
            Write-Verbose "Changes found for '$FilePath'."
            return $diff
        }
        else {
            Write-Verbose "No changes found for '$FilePath'."
            return $null
        }
    }
    catch {
        Write-Warning "Error getting changes for '$FilePath': $_"
        return $null # Or throw, depending on desired error handling
    }
    Write-Verbose "Exiting Get-FileChanges for '$FilePath'"
}


function script:Get-GitDiffSummary {
    param(
        [Parameter(Mandatory)]
        [string]$DiffContent,
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    Write-Verbose "Entering Get-GitDiffSummary for '$FilePath'"
    
    # Add validation for $DiffContent
    if ([string]::IsNullOrWhiteSpace($DiffContent)) {
        Write-Warning "Empty diff content for '$FilePath'. Cannot generate summary."
        return @{
            SystemPrompt = ""
            UserPrompt   = "No changes detected in '$FilePath'."
        }
    }

    # Improved line counting logic
    $diffLines = $DiffContent -split "`n"
    $lineCount = 0
    $addedLines = 0
    $removedLines = 0

    foreach ($line in $diffLines) {
        if ($line -match '^@@') {
            # This is a hunk header line like @@ -0,0 +1,110 @@
            # Extract the line numbers and counts
            if ($line -match '@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@') {
                $oldStart = [int]$matches[1]
                $oldCount = if ($matches[2] -ne '') { [int]$matches[2] } else { 1 }
                $newStart = [int]$matches[3]
                $newCount = if ($matches[4] -ne '') { [int]$matches[4] } else { 1 }
                
                # For new files, oldCount will be 0
                if ($oldCount -eq 0) {
                    $addedLines += $newCount
                    $lineCount += $newCount
                }
                # For deleted files, newCount will be 0
                elseif ($newCount -eq 0) {
                    $removedLines += $oldCount
                    $lineCount += $oldCount
                }
                # For modified files, count both
                else {
                    $lineCount += [Math]::Max($oldCount, $newCount)
                }
            }
            continue
        }

        # Count individual lines
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') {
            $addedLines++
        }
        elseif ($line -match '^-' -and $line -notmatch '^---') {
            $removedLines++
        }
    }

    # For completely new files, use a special message
    $isNewFile = $DiffContent -match 'new file mode'
    $isDeletedFile = $DiffContent -match 'deleted file mode'
    
    $fileStatus = if ($isNewFile) {
        "New file"
    }
    elseif ($isDeletedFile) {
        "Deleted file"
    }
    else {
        "Modified file"
    }

    $summary = @"
File: '$FilePath' ($fileStatus)
Line Changes: $lineCount lines changed.
Added lines: $addedLines lines added.
Removed lines: $removedLines lines removed.
"@

    Write-Verbose "Git Diff Summary for '$FilePath': $($summary)"

    # Construct prompts - System prompt can be more generic, User prompt is file-specific summary
    $systemPrompt = @"
You are a highly skilled Git diff summarizer, tasked with providing concise and technically accurate summaries of code changes, focusing on the *purpose* and *impact* of the modifications.  Analyze the provided git diff and identify:

- The *type* of change (e.g., bug fix, feature addition, refactoring, performance improvement).
- The *functional area* or *subsystem* affected by the changes.
- The *core problem* being addressed or the *benefit* being introduced.
- The *key technical modifications* made to achieve this.

Focus on conveying the *significance* and *reasoning* behind the changes, not just the mechanics of the code modifications.  Summarize in 1-3 sentences, using technical terms and active voice.  Omit file paths and obvious metadata. **Return the summary as plain text. Do not format the output as a code block or use markdown.**
"@

    $userPrompt = "Summarize these changes:`n$DiffContent"

    Write-Verbose "Exiting Get-GitDiffSummary for '$FilePath'"
    return @{
        SystemPrompt = $systemPrompt
        UserPrompt   = $userPrompt
    }
}


function script:Build-ChangeSummary {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Changes
    )
    Write-Verbose "Entering Build-ChangeSummary"
    $summary = ""

    if ($Changes.TextChanges) {
        $summary += "Text File Changes:`n"
        foreach ($change in $Changes.TextChanges) {
            $summary += "- $($change.File): $($change.Summary.UserPrompt)`n" # Or use a more concise version of summary if available
        }
    }

    if ($Changes.BinaryFiles) {
        $summary += "`nBinary File Changes:`n"
        foreach ($file in $Changes.BinaryFiles) {
            $summary += "- $($file)`n" # Just list binary files
        }
    }

    if ($Changes.OtherChanges) {
        $summary += "`nOther Changes:`n"
        foreach ($change in $Changes.OtherChanges) {
            $summary += "- $($change)`n" # List other types of changes if detected
        }
    }
    Write-Verbose "Exiting Build-ChangeSummary"
    return $summary
}

#endregion  Script-Level Helper Functions

function New-LLMCommitMessage {
    [CmdletBinding()]
    [Alias('gptcommit', 'geminicommit')] # Keep both aliases for backward compatibility
    param(
        [Parameter()]
        [ValidateSet("Ollama", "Gemini")]
        [string]$LLMProvider, # Optional Provider - defaults to config or Ollama
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Model, # Model parameter - will be mandatory depending on provider in PROCESS block
        [Parameter()]
        [switch]$StagedOnly
    )

    begin {
        # --- Load LLM Configuration at the beginning of New-LLMCommitMessage's begin block ---
        try {
            if (-not $script:LLMConfiguration) {
                # Check if already loaded
                $script:ConfigFile = Join-Path -Path $HOME -ChildPath ".llmconfig.json"
                if (!(Test-Path -Path $script:ConfigFile -PathType Leaf)) {
                    throw "LLM config file not found at '$script:ConfigFile'."
                }
                $script:LLMConfiguration = Get-Content -Path $script:ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop
                Write-Verbose "LLM Configuration loaded within New-LLMCommitMessage from '$script:ConfigFile'."
            }
            else {
                Write-Verbose "LLM Configuration already loaded (likely by script-level initialization or calling function)."
            }
        }
        catch {
            Write-Warning "Warning: Error loading LLM Configuration in New-LLMCommitMessage: $_ Using default provider and API settings."
            # If config loading fails, defaults will be used in process block
        }
        # --- End Config Loading ---
    }

    process {
        try {
            Write-Verbose "Starting New-LLMCommitMessage"

            # Determine LLM Provider - Parameter > Config > Default "Ollama"
            $llmProviderForCall = if ($LLMProvider) {
                $LLMProvider
            }
            elseif ($script:LLMConfiguration.DefaultProvider) {
                $script:LLMConfiguration.DefaultProvider
            }
            else {
                "Ollama" # Default if no config and no parameter
            }
            Write-Verbose "Using LLM Provider: '$llmProviderForCall'"

            # Parameter validation and defaults based on LLMProvider
            if (-not $Model) {
                switch ($llmProviderForCall) {
                    "Ollama" { $Model = "gemma3:4b" } # Default Ollama model
                    "Gemini" { $Model = "gemini-2.0-flash" } # Default Gemini model
                }
                Write-Verbose "Model parameter not provided, using default model '$Model' for '$llmProviderForCall' provider."
            }

            Write-Verbose "Getting changed files"
            $stagedFiles = @(git diff --name-only --cached)
            $unstagedFiles = if (-not $StagedOnly) { @(git diff --name-only) } else { @() }
            
            # If no staged files but we have unstaged files, use those regardless of StagedOnly
            if (-not $stagedFiles -and $unstagedFiles) {
                Write-Warning "No staged files found. Using all modified files instead."
                $StagedOnly = $false  # Override StagedOnly to use unstaged files
            }
            
            # Check if we have any files to analyze (staged or unstaged)
            if (-not ($stagedFiles + $unstagedFiles)) {
                throw "No modified files found in the repository. Nothing to commit."
            }

            Write-Verbose "Analyzing changes"
            $changes = script:Get-FileChangeSummary -StagedFiles $stagedFiles -UnstagedFiles $unstagedFiles

            # Process text file changes
            $textChanges = @()
            foreach ($file in $changes.TextFiles) {
                Write-Verbose "Getting changes for $file"
                $isStaged = $file -in $stagedFiles
                $diff = script:Get-FileChanges -FilePath $file -IsStaged $isStaged
                if ($diff) {
                    # This check is good, but let's make it more explicit
                    if ($null -eq $diff -or $diff -isnot [string] -or $diff -eq '') {
                        Write-Verbose "Skipping empty or null diff for $file"
                        continue  # Skip this file if diff is null, not a string, or empty
                    }
                    $diffSummaryPrompts = script:Get-GitDiffSummary -DiffContent $diff -FilePath $file
                    # Store both system and user prompts for API calls
                    $textChanges += @{
                        File    = $file
                        Summary = $diffSummaryPrompts # Now stores hashtable of prompts
                    }
                }
            }
            $changes.TextChanges = $textChanges
            $changeSummary = script:Build-ChangeSummary -Changes $changes

            $systemPrompt = @"
You are an expert in writing Git commit messages that adhere to Linux kernel contribution standards. Your goal is to create a well-structured and informative commit message based on a provided change summary. Follow these guidelines strictly:

- **Subject Line:**
    - Start with an *imperative verb* (e.g., Fix, Add, Update, Refactor).
    - Aim for a concise summary under 50 characters, maximum 72.
    - Capitalize the first word. No period at the end.
    - Optionally, begin with a *subsystem prefix* followed by a colon and a space (e.g., `net:`, `fs:`, `drivers:`).  Infer the most relevant subsystem from the change summary if possible.
- **Body (separated by a blank line):**
    - Explain the *motivation* for the change: *Why* is this change necessary? What problem does it solve? What improvement does it bring?
    - Briefly describe *what* was changed to address the problem or achieve the improvement.
    - If applicable, mention *how* the change achieves its goal, but keep it concise. Focus more on *what* and *why*.
    - Use bullet points for listing specific changes or aspects of the commit.
    - Wrap all lines at 72 characters.
    - Use active voice and technical terminology.

Write a commit message that is clear, concise, and informative, providing sufficient context for reviewers and future maintainers to understand the purpose and impact of the changes. **Return the commit message as plain text. Do not format the output as a code block or use markdown.**
"@

            $userPrompt = @"
Write a commit message for these changes:

$changeSummary

Format as a proper git commit message with summary and details.
"@


            # Prepare parameter splat based on LLMProvider - Common parameters
            $apiParams = @{
                Model        = $Model
                UserPrompt   = $userPrompt
                SystemPrompt = $systemPrompt
            }

            Write-Verbose "Generating commit message using $($llmProviderForCall) API"
            $commitMessage = switch ($llmProviderForCall) {
                "Ollama" {
                    Invoke-OllamaAIGenAPI @apiParams # Splatting for Ollama - no Ollama-specific params here
                }
                "Gemini" {
                    Invoke-GeminiAIGenAPI @apiParams # Splatting for Gemini
                }
                default {
                    throw "Unsupported LLM Provider: $($llmProviderForCall)" # Should not reach here due to ValidateSet
                }
            }
            Write-Output $commitMessage

        }
        catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
    end {
        Write-Verbose "New-LLMCommitMessage completed."
    }
}
