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
        [switch]$StagedOnly,
        
        [Parameter()]
        [string]$Context # New parameter for user-provided context/seed for the commit message
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
            $changes = Get-FileChangeSummary -StagedFiles $stagedFiles -UnstagedFiles $unstagedFiles

            # Process text file changes
            # Process text file changes
            $textChanges = @()
            foreach ($file in $changes.TextFiles) {
                Write-Verbose "Getting changes for $file"
                $isStaged = $file -in $stagedFiles
    
                # Get file status first
                $fileStatus = Get-GitFileStatus -FilePath $file
                Write-Verbose "File status for $file`: $fileStatus"
    
                $diff = Get-FileChanges -FilePath $file -IsStaged $isStaged
                if ($diff) {
                    if ($null -eq $diff -or $diff -isnot [string] -or $diff -eq '') {
                        Write-Verbose "Skipping empty or null diff for $file"
                        continue
                    }
        
                    # Get summary from LLM for this file's changes
                    $diffSummary = Get-GitDiffSummary -DiffContent $diff -FilePath $file -FileStatus $fileStatus -LLMProvider $llmProviderForCall -Model $Model
        
                    # Store the summary and file info
                    $textChanges += @{
                        File    = $file
                        Summary = $diffSummary
                    }
                }
            }
            $changes.TextChanges = $textChanges
            $changeSummary = Build-ChangeSummary -Changes $changes
            if (-not [string]::IsNullOrWhiteSpace($Context)) {
                Write-Verbose "User provided context: $Context"
                # Prepend the user context to the change summary
                $changeSummary = "USER CONTEXT: $Context`n`n$changeSummary"
            }

            $systemPrompt = @"
You are an expert in writing Git commit messages. Your goal is to create a well-structured and informative commit message based on a provided change summary. Follow these guidelines strictly:

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

            $userPrompt = if (-not [string]::IsNullOrWhiteSpace($Context)) {
                @"
Write a commit message for these changes:

$changeSummary

IMPORTANT: Pay special attention to the USER CONTEXT at the beginning, which provides the user's intent or explanation for these changes. Incorporate this context into your commit message.

Format as a proper git commit message with summary and details.
"@
            }
            else {
                @"
Write a commit message for these changes:

$changeSummary

Format as a proper git commit message with summary and details.
"@
            }

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
