Import-Module .\LLMCommit\LLMCommit.psm1 -Force
Push-Location C:\git\LLMCommit
new-LLMCommitMessage -Context "refactoring for better change detection" -LLMProvider Ollama