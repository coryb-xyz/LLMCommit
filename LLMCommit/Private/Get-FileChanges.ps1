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