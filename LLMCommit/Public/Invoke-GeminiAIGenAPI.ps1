function Invoke-GeminiAIGenAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrompt, 
        [Parameter(Mandatory)]
        [string]$SystemPrompt, 
        [Parameter()]
        [string]$Model, 
        [Parameter()]
        [int]$MaxRetries = 5, 
        [Parameter()]
        [int]$InitialRetryIntervalSeconds = 1 
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
        $Model = $Model ?? $script:LLMConfiguration.DefaultGeminiModel

        Write-Verbose "Initializing Invoke-GeminiAIGenAPI for model '$Model'"
        $GeminiEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
        $ApiEndpoint = "$GeminiEndpointBase/$($Model):generateContent"
    }
    process {
        $plainTextApiKey = $null
        $plainTextApiKeyPtr = $null
        try {
            Write-Verbose "Retrieving Gemini API Key from Secret Management"
            $secureApiKey = Get-Secret -Name $script:LLMConfiguration.GeminiApiKeyName

            # Securely convert SecureString to plain text string
            $plainTextApiKeyPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
            $plainTextApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($plainTextApiKeyPtr)
            $ApiEndpointWithKey = "$($ApiEndpoint)?key=$plainTextApiKey"

            Write-Verbose "API Endpoint URI: $($ApiEndpointWithKey)"

            # Combine System and User prompts here for Gemini API
            $combinedPrompt = "$SystemPrompt`n`n$UserPrompt"

            $body = @{ # Simplified body - only user content, using combined prompt
                contents = @(
                    @{
                        role  = "user"
                        parts = @(
                            @{ text = $combinedPrompt }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 10

            $retryCount = 0
            $retryIntervalSeconds = $InitialRetryIntervalSeconds
            $continueRetrying = $true

            while ($continueRetrying) {
                $retryCount++
                Write-Verbose "Attempting API request (Retry: $($retryCount) of $($MaxRetries))"

                $restMethodParams = @{ # Splatting for Invoke-RestMethod
                    Uri         = $ApiEndpointWithKey
                    Method      = 'Post'
                    ContentType = 'application/json'
                    Body        = $body
                    ErrorAction = 'Stop'
                }
                Write-Debug "Invoke-RestMethod Parameters: $($restMethodParams | ConvertTo-Json -Depth 4)"

                try {
                    $response = Invoke-RestMethod @restMethodParams
                    Write-Verbose "API request successful."
                    $continueRetrying = $false # Exit retry loop on success
                }
                catch {
                    if ($_.Exception.Response -is [System.Net.HttpWebResponse] -and $_.Exception.Response.StatusCode -eq 429) {
                        # Rate Limit Error
                        if ($retryCount -ge $MaxRetries) {
                            Write-Error "Maximum retry attempts reached for rate limit. Aborting API call." -ErrorAction Stop
                            $continueRetrying = $false # Exit retry loop after max retries
                        }
                        else {
                            Write-Warning "Rate limit hit (429). Retrying in $($retryIntervalSeconds) seconds... (Attempt $($retryCount) of $($MaxRetries))"
                            Start-Sleep -Seconds $retryIntervalSeconds
                            $retryIntervalSeconds *= 2 # Exponential backoff
                        }
                    }
                    else {
                        # Other API errors - re-throw for handling in calling function
                        Write-Error "API request failed with error (Retry attempt $($retryCount)): $($_.Exception.Message)"
                        throw # Re-throw exception
                    }
                }
            }

            # Extract generated text from response
            $generatedText = $response.candidates[0].content.parts[0].text
            Write-Verbose "Generated text extracted."
            return $generatedText

        }
        catch {
            Write-Error "Error in Invoke-GeminiAIGenAPI: $_" -ErrorAction Stop
        }
        finally {
            # Securely clear sensitive data from memory
            if ($plainTextApiKeyPtr) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($plainTextApiKeyPtr)
            }
        }
    }
    end {
        Write-Verbose "Invoke-GeminiAIGenAPI completed for model '$Model'."
    }
}