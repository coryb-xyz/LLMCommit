function Get-FileChangeSummary {
    param(
        [Parameter(Mandatory = $false)] 
        [string[]]$StagedFiles = @(),
        [Parameter(Mandatory = $false)] 
        [string[]]$UnstagedFiles = @() 
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