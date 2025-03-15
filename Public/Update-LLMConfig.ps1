# Initialize script-level variables for argument completion
$script:ConfigFile = Join-Path -Path $HOME -ChildPath ".llmconfig.json"
$script:configKeys = $null # Will be populated during dot-sourcing

# Helper function to load config keys - can be called both at dot-sourcing time and during tab completion
function script:Get-ConfigKeys {
    try {
        # Ensure config file exists
        if (!(Test-Path -Path $script:ConfigFile -PathType Leaf)) {
            $defaultConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "default-llm-config.json"
            if (Test-Path -Path $defaultConfigPath -PathType Leaf) {
                Copy-Item -Path $defaultConfigPath -Destination $script:ConfigFile -Force
            }
            else {
                # If default config doesn't exist, return hardcoded fallback keys
                return @("DefaultProvider", "OllamaMaxContextSize", "OllamaWordsPerTokenHeuristic", 
                         "OllamaSafetyMarginPercent", "ApiMaxRetries", "ApiInitialRetryIntervalSeconds")
            }
        }
        
        # Read config and extract keys
        $config = Get-Content -Path $script:ConfigFile -Raw | ConvertFrom-Json
        return ($config | Get-Member -MemberType NoteProperty).Name
    }
    catch {
        # If any error occurs, return hardcoded fallback keys
        return @("DefaultProvider", "OllamaMaxContextSize", "OllamaWordsPerTokenHeuristic", 
                 "OllamaSafetyMarginPercent", "ApiMaxRetries", "ApiInitialRetryIntervalSeconds")
    }
}

# Populate config keys at dot-sourcing time
$script:configKeys = Get-ConfigKeys

# Register the argument completer for Update-LLMConfig -Setting parameter
Register-ArgumentCompleter -CommandName 'Update-LLMConfig' -ParameterName 'Setting' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # Use cached keys if available, otherwise regenerate them
    $keys = if ($script:configKeys) { $script:configKeys } else { $script:configKeys = Get-ConfigKeys }
    
    # Filter and return matching keys
    $keys | Where-Object { $_ -like "$wordToComplete*" }
}

function Update-LLMConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias("ConfigSetting")]
        [string]$Setting,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )
    
    begin {
        Write-Verbose "Starting Update-LLMConfig for setting '$Setting'"
    }
    
    process {
        try {
            # Check if config file exists, create with defaults if not
            if (!(Test-Path -Path $script:ConfigFile -PathType Leaf)) {
                Write-Verbose "Config file not found. Creating with defaults."
                $defaultConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "default-llm-config.json"
                if (!(Test-Path -Path $defaultConfigPath -PathType Leaf)) {
                    throw "Default config file 'default-llm-config.json' not found in script directory '$PSScriptRoot'."
                }
                Copy-Item -Path $defaultConfigPath -Destination $script:ConfigFile -Force
            }

            # Read existing config
            Write-Verbose "Reading config from '$script:ConfigFile'"
            $config = Get-Content -Path $script:ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop

            # Validate Setting parameter
            $validSettings = ($config | Get-Member -MemberType NoteProperty).Name
            if ($Setting -notin $validSettings) {
                throw "Invalid Setting: '$Setting'. Valid settings are: $($validSettings -join ', ')"
            }

            # Update the setting with type conversion
            $settingType = $config | Get-Member -MemberType NoteProperty | 
                           Where-Object { $_.Name -eq $Setting } | 
                           Select-Object -ExpandProperty Definition
            
            if ($settingType -like "*[int]*") {
                $config.$Setting = [int]$Value
            } 
            elseif ($settingType -like "*[double]*") {
                $config.$Setting = [double]$Value
            } 
            else {
                $config.$Setting = $Value # Treat as string by default
            }

            # Save updated config
            Write-Verbose "Saving updated config to '$script:ConfigFile'"
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigFile -Encoding UTF8

            # Update script-level configKeys to reflect any changes
            $script:configKeys = ($config | Get-Member -MemberType NoteProperty).Name
            
            Write-Host "Successfully updated LLM config setting '$Setting' to '$Value'."
        }
        catch {
            Write-Error "Error updating LLM config: $_" -ErrorAction Stop
        }
    }
    
    end {
        Write-Verbose "Update-LLMConfig completed."
    }
}