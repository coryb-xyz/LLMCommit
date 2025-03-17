function Get-GitFileStatus {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    # Use git status with porcelain format for reliable parsing
    $status = git status --porcelain=v1 -- "$FilePath" | Out-String
    
    if ($status -match "^A") {
        return "New"
    }
    elseif ($status -match "^D") {
        return "Deleted"
    }
    elseif ($status -match "^R") {
        return "Renamed"
    }
    elseif ($status -match "^M" -or $status -match "^ M") {
        return "Modified"
    }
    else {
        # Check diff directly as fallback
        $diff = git diff --name-status -- "$FilePath" | Out-String
        
        if ($diff -match "^A") {
            return "New"
        }
        elseif ($diff -match "^D") {
            return "Deleted"
        }
        elseif ($diff -match "^R") {
            return "Renamed"
        }
        elseif ($diff -match "^M") {
            return "Modified"
        }
        else {
            return "Unknown"
        }
    }
}