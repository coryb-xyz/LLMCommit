function Build-ChangeSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Changes
    )
    Write-Verbose "Entering Build-ChangeSummary"
    
    # Use StringBuilder for better performance with large summaries
    $summary = [System.Text.StringBuilder]::new()
    
    # Group text changes by status
    $newFiles = $Changes.TextChanges | Where-Object { $_.Summary.FileStatus -eq "New" }
    $modifiedFiles = $Changes.TextChanges | Where-Object { $_.Summary.FileStatus -eq "Modified" }
    $deletedFiles = $Changes.TextChanges | Where-Object { $_.Summary.FileStatus -eq "Deleted" }
    $otherFiles = $Changes.TextChanges | Where-Object { 
        $_.Summary.FileStatus -notin @("New", "Modified", "Deleted") 
    }
    
    # Add new files section
    if ($newFiles) {
        [void]$summary.AppendLine("New Files:")
        foreach ($change in $newFiles) {
            [void]$summary.AppendLine("- $($change.File): $($change.Summary.Summary)")
        }
        [void]$summary.AppendLine()
    }
    
    # Add modified files section
    if ($modifiedFiles) {
        [void]$summary.AppendLine("Modified Files:")
        foreach ($change in $modifiedFiles) {
            [void]$summary.AppendLine("- $($change.File): $($change.Summary.Summary)")
        }
        [void]$summary.AppendLine()
    }
    
    # Add deleted files section
    if ($deletedFiles) {
        [void]$summary.AppendLine("Deleted Files:")
        foreach ($change in $deletedFiles) {
            [void]$summary.AppendLine("- $($change.File): $($change.Summary.Summary)")
        }
        [void]$summary.AppendLine()
    }
    
    # Add other files section
    if ($otherFiles) {
        [void]$summary.AppendLine("Other Changes:")
        foreach ($change in $otherFiles) {
            [void]$summary.AppendLine("- $($change.File): $($change.Summary.Summary)")
        }
        [void]$summary.AppendLine()
    }

    # Add binary files section
    if ($Changes.BinaryChanges) {
        [void]$summary.AppendLine("Binary File Changes:")
        foreach ($change in $Changes.BinaryChanges) {
            [void]$summary.AppendLine("- $($change.Action) $($change.Count) $($change.Extension) files in $($change.Directory)")
        }
    }
    
    Write-Verbose "Exiting Build-ChangeSummary"
    return $summary.ToString()
}