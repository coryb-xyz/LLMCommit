function Invoke-OllamaAIGenAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrompt, # User prompt content
        [Parameter(Mandatory)]
        [string]$SystemPrompt, # System prompt content
        [Parameter()]
        [string]$Model, # Default Ollama model
        [Parameter()]
        [int]$MaxRetries = 3, # Optional: Retry attempts for potential issues
        [Parameter()]
        [int]$InitialRetryIntervalSeconds = 1 # Optional: Initial retry wait (seconds)
    )
    begin {
        # Load LLM Configuration at the beginning of Invoke-OllamaAIGenAPI's begin block
        try {
            if (-not $script:LLMConfiguration) {
                # Check if already loaded (e.g., by New-LLMCommitMessage)
                $script:ConfigFile = Join-Path -Path $HOME -ChildPath ".llmconfig.json"
                if (!(Test-Path -Path $script:ConfigFile -PathType Leaf)) {
                    throw "LLM config file not found at '$script:ConfigFile'."
                }
                $script:LLMConfiguration = Get-Content -Path $script:ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop
                Write-Verbose "LLM Configuration loaded within Invoke-OllamaAIGenAPI from '$script:ConfigFile'."
            }
            else {
                Write-Verbose "LLM Configuration already loaded (likely by calling function)."
            }

            # Retrieve Ollama Endpoint from configuration, with a default fallback
            $script:OllamaEndpoint = if ($script:LLMConfiguration.OllamaEndpoint) {
                $script:LLMConfiguration.OllamaEndpoint
            }
            else {
                "http://localhost:11434/api/chat" # Default endpoint if not in config
                Write-Warning "OllamaEndpoint not found in config file. Using default: 'http://localhost:11434/api/chat'."
            }
            Write-Verbose "Ollama Endpoint: '$script:OllamaEndpoint'"
            $Model = if ($Model) { $model } else { $script:LLMConfiguration.DefaultOllamaModel }
            Write-Verbose "Initializing Invoke-OllamaAIGenAPI for model '$Model'"


        }
        catch {
            Write-Warning "Warning: Error loading LLM Configuration in Invoke-OllamaAIGenAPI: $_ Using default context sizing and endpoint values."
            # If config loading fails, use hardcoded defaults for context sizing and endpoint
            $script:OllamaEndpoint = "http://localhost:11434/api/chat" # Fallback default endpoint
        }
    }
    process {
        try {
            Write-Verbose "Sending request to Ollama API (Model: '$Model')"          

            $body = @{
                model    = $Model
                messages = @(
                    @{
                        role    = "system"
                        content = $SystemPrompt
                    }
                    @{
                        role    = "user"
                        content = $UserPrompt
                    }
                )
                stream   = $false # Set to false for non-streaming response
                format   = @{ # Request structured JSON response
                    type       = "object"
                    properties = @{
                        message = @{
                            type        = "string"
                            description = "The generated message content"
                        }
                    }
                    required   = @("message")
                }
                options  = @{
                    temperature = 0.3 # Temperature setting (adjust for desired creativity)
                }
            }

            $jsonBody = $body | ConvertTo-Json -Depth 10
            Write-Debug "Ollama API Request Body: $($jsonBody)"

            $retryCount = 0
            $retryIntervalSeconds = $InitialRetryIntervalSeconds
            $continueRetrying = $true

            while ($continueRetrying) {
                $retryCount++
                Write-Verbose "Attempting API request (Retry: $($retryCount) of $($MaxRetries))"

                $restMethodParams = @{
                    Uri         = $script:OllamaEndpoint
                    Method      = 'Post'
                    ContentType = "application/json"
                    Body        = $jsonBody
                    ErrorAction = 'Stop' # Stop on error for retry logic
                }
                Write-Debug "Invoke-RestMethod Parameters: $($restMethodParams | ConvertTo-Json -Depth 4)"

                try {
                    $response = Invoke-RestMethod @restMethodParams
                    Write-Verbose "Ollama API request successful."
                    $continueRetrying = $false # Exit retry loop on success
                    break # Exit while loop after successful attempt
                }
                catch {
                    Write-Warning "Ollama API request failed (Retry attempt $($retryCount)): $($_.Exception.Message)"
                    if ($retryCount -ge $MaxRetries) {
                        Write-Error "Maximum retry attempts reached for Ollama API. Aborting call." -ErrorAction Stop
                        $continueRetrying = $continueRetrying = $false # Exit retry loop after max retries
                    }
                    else {
                        Write-Warning "Retrying in $($retryIntervalSeconds) seconds... (Attempt $($retryCount) of $($MaxRetries))"
                        Start-Sleep -Seconds $retryIntervalSeconds
                        $retryIntervalSeconds *= 2 # Exponential backoff
                    }
                }
            }
            # In Invoke-OllamaAIGenAPI, before extracting the generated text
            Write-Verbose "Response structure: $($response | ConvertTo-Json -Depth 3)"

            # Then try different approaches to extract the text
            try {
                # Try direct access if the response is already structured
                if ($response.message -and $response.message.content) {
                    $generatedText = $response.message.content
                    Write-Verbose "Extracted text directly from response.message.content"
                }
                # If content is JSON, try to parse it
                elseif ($response.message -and $response.message.content -and $response.message.content -match '^\s*\{') {
                    $generatedText = ($response.message.content | ConvertFrom-Json).message
                    Write-Verbose "Extracted text from JSON in response.message.content"
                }
                # Fallback to the whole response if we can't find the expected structure
                else {
                    $generatedText = $response | ConvertTo-Json -Depth 3
                    Write-Verbose "Could not find expected message structure, returning full response"
                }
            }
            catch {
                Write-Warning "Error extracting message from Ollama response: $_"
                $generatedText = "Error extracting message from Ollama response. Raw response: $($response | ConvertTo-Json -Depth 1)"
            }
            # Extract the generated message content
            $generatedText = ($response.message.content | ConvertFrom-Json).message
            Write-Verbose "Generated text extracted."
            return $generatedText

        }
        catch {
            Write-Error "Error in Invoke-OllamaAIGenAPI: $_" -ErrorAction Stop # Catch any errors not handled in retry loop
        }
    }
    end {
        Write-Verbose "Invoke-OllamaAIGenAPI completed for model '$Model'."
    }
}