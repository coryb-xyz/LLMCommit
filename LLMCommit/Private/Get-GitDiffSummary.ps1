function Get-GitDiffSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DiffContent,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter()]
        [string]$FileStatus = "Unknown",
        [Parameter(Mandatory)]
        [string]$LLMProvider,
        [Parameter()]
        [string]$Model
    )
    
    Write-Verbose "Entering Get-GitDiffSummary for '$FilePath' (Status: $FileStatus)"
    
    # Add validation for $DiffContent
    if ([string]::IsNullOrWhiteSpace($DiffContent)) {
        Write-Warning "Empty diff content for '$FilePath'. Cannot generate summary."
        return "No changes detected in '$FilePath'."
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
                $oldCount = if ($matches[2] -ne '') { [int]$matches[2] } else { 1 }
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

    # If file status wasn't provided, try to determine it from diff content
    if ($FileStatus -eq "Unknown") {
        if ($DiffContent -match 'new file mode') {
            $FileStatus = "New"
        }
        elseif ($DiffContent -match 'deleted file mode') {
            $FileStatus = "Deleted"
        }
        else {
            $FileStatus = "Modified"
        }
    }
    
    # Get file extension for additional context
    $extension = [System.IO.Path]::GetExtension($FilePath)
    if ([string]::IsNullOrEmpty($extension)) {
        $extension = "no extension"
    }

    $fileSummary = @"
File: '$FilePath' ($FileStatus file, $extension)
Line Changes: $lineCount lines changed.
Added lines: $addedLines lines added.
Removed lines: $removedLines lines removed.
"@

    Write-Verbose "Git Diff Summary for '$FilePath': $($fileSummary)"

    # Construct prompts for the LLM
    $systemPrompt = @"
You are a highly skilled Git diff summarizer, tasked with providing concise and technically accurate summaries of code changes, focusing on the *purpose* and *impact* of the modifications. Analyze the provided git diff and identify:

- The *type* of change (e.g., bug fix, feature addition, refactoring, performance improvement).
- The *functional area* or *subsystem* affected by the changes.
- The *core problem* being addressed or the *benefit* being introduced.
- The *key technical modifications* made to achieve this.

Focus on conveying the *significance* and *reasoning* behind the changes, not just the mechanics of the code modifications. Summarize in 1-3 sentences, using technical terms and active voice. Omit file paths and obvious metadata. **Return the summary as plain text. Do not format the output as a code block or use markdown.**
"@

    # Enhanced user prompt with file status context
    $userPrompt = @"
Summarize these changes to a $FileStatus $extension file:
$DiffContent

File Summary: $fileSummary
"@

    # Create params for the LLM API call
    $apiParams = @{
        SystemPrompt = $systemPrompt
        UserPrompt = $userPrompt
    }
    
    # Add model if specified
    if ($Model) {
        $apiParams.Model = $Model
    }
    
    Write-Verbose "Calling $LLMProvider API to summarize changes for '$FilePath'"
    
    # Call the appropriate provider API to get the summary
    $summary = switch ($LLMProvider) {
        "Ollama" { Invoke-OllamaAIGenAPI @apiParams }
        "Gemini" { Invoke-GeminiAIGenAPI @apiParams }
        default { throw "Unsupported LLM Provider: $LLMProvider" }
    }
    
    Write-Verbose "Received summary from $LLMProvider for '$FilePath': $summary"
    
    # Return the summary along with file status for categorization
    return @{
        Summary = $summary
        FileStatus = $FileStatus
    }
}