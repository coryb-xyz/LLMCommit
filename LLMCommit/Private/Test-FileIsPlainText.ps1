function Test-FileIsPlainText {
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