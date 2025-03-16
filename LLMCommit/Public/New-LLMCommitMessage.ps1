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
        [Parameter(Mandatory=$false)]  # Change from Mandatory to optional
        [string[]]$StagedFiles = @(),   # Provide default empty array
        [Parameter(Mandatory=$false)]  # Change from Mandatory to optional
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
You are a helpful AI assistant specialized in understanding code changes in Git diff format and summarizing them concisely.
Your goal is to provide a very short, informative summary of the changes in each file, suitable for inclusion in a commit message.
Focus on the high-level intent and impact of the changes, not just the line-by-line modifications. Be extremely concise.
"@

    $userPrompt = @"
Summarize the following code changes in Git diff format for file '$FilePath'. Be extremely concise and focus on the high-level changes.
Diff Content:
``````diff
$DiffContent
powershell

Copy code
File Summary: $summary
"@

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


function script:Get-CommitMessagePrompt {
    param(
        [Parameter(Mandatory)]
        [string]$ChangeSummary
    )
    Write-Verbose "Entering Get-CommitMessagePrompt"

    $systemPrompt = @"
You are an expert AI assistant specialized in generating concise and informative commit messages for Git.
Analyze the provided summary of code changes and generate a commit message that accurately and briefly describes these changes.
Follow conventional commit message format. Start with a concise summary in the imperative mood (e.g., 'Fix bug...', 'Add feature...').
If applicable, include a more detailed explanation after the summary, separated by a blank line. Be brief and to the point
"@

    $userPrompt = @"
Based on the following summary of code changes, generate a concise and informative commit message.
Change Summary:
``````
$ChangeSummary
``````
"@
    Write-Verbose "Exiting Get-CommitMessagePrompt"
    return @{
        SystemPrompt = $systemPrompt
        UserPrompt   = $userPrompt
    }
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

            $commitMessagePrompts = script:Get-CommitMessagePrompt -ChangeSummary $changeSummary


            # Prepare parameter splat based on LLMProvider - Common parameters
            $apiParams = @{
                Model        = $Model
                UserPrompt   = $commitMessagePrompts.UserPrompt
                SystemPrompt = $commitMessagePrompts.SystemPrompt
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
