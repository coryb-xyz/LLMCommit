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
                # If default config doesn't exist, return empty array
                return @()
            }
        }

        # Read config and extract keys
        $config = Get-Content -Path $script:ConfigFile -Raw | ConvertFrom-Json
        return ($config | Get-Member -MemberType NoteProperty).Name
    }
    catch {
        # If any error occurs, return empty array
        return @()
    }
}

# Helper function to initialize config file
function script:Initialize-ConfigFile {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Switch] $Force
    )
    try {
        $defaultConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "default-llm-config.json"
        if (!(Test-Path -Path $defaultConfigPath -PathType Leaf)) {
            throw "Default config file 'default-llm-config.json' not found in script directory '$PSScriptRoot'."
        }

        if (!(Test-Path $script:ConfigFile) -or $Force) {
            Write-Verbose "Initializing config file with defaults from '$defaultConfigPath'"
            Copy-Item -Path $defaultConfigPath -Destination $script:ConfigFile -Force
            Write-Verbose "Successfully initialized LLM config file at '$script:ConfigFile'."
        }

        # Refresh config keys
        $script:configKeys = Get-ConfigKeys

       
    }
    catch {
        Write-Error "Error initializing LLM config file: $_"
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
    [CmdletBinding(DefaultParameterSetName = 'Update')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Update')]
        [ValidateNotNullOrEmpty()]
        [Alias("ConfigSetting")]
        [string]$Setting,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Update')]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory, ParameterSetName = 'Initialize')]
        [switch]$Initialize,

        [Parameter(ParameterSetName = 'Initialize')]
        [switch] $Force

    )

    begin {
        Write-Verbose "Starting Update-LLMConfig"
    }

    process {
        try {
            # Handle initialization if requested
            if ($Initialize) {
                Initialize-ConfigFile -Force:$Force
                return
            }

            # For the update path, continue with the existing functionality
            Write-Verbose "Processing update for setting '$Setting'"

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
                # If setting doesn't exist, add it as a string value
                Write-Verbose "Adding new setting '$Setting' to config"
                Add-Member -InputObject $config -MemberType NoteProperty -Name $Setting -Value $Value
            }
            else {
                # Setting exists, determine its type and convert the new value accordingly
                $currentValue = $config.$Setting

                if ($null -eq $currentValue) {
                    # If current value is null, just use the string value
                    $config.$Setting = $Value
                }
                elseif ($currentValue -is [int] -or $currentValue -is [long]) {
                    # Try to convert to integer
                    try {
                        $config.$Setting = [int]$Value
                    }
                    catch {
                        throw "Value for '$Setting' must be an integer (current type: $($currentValue.GetType().Name))."
                    }
                }
                elseif ($currentValue -is [double] -or $currentValue -is [float] -or $currentValue -is [decimal]) {
                    # Try to convert to double
                    try {
                        $config.$Setting = [double]$Value
                    }
                    catch {
                        throw "Value for '$Setting' must be a decimal number (current type: $($currentValue.GetType().Name))."
                    }
                }
                elseif ($currentValue -is [bool]) {
                    # Try to convert to boolean
                    if ($Value -in @('true', 'false', '0', '1', '$true', '$false')) {
                        $config.$Setting = [bool]::Parse($Value.ToLower().Replace('$', ''))
                    }
                    else {
                        throw "Value for '$Setting' must be a boolean (true/false) (current type: Boolean)."
                    }
                }
                else {
                    # Default to string for all other types
                    $config.$Setting = $Value
                }
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
