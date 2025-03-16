# LLMCommit

A PowerShell module for generating meaningful Git commit messages using AI language models.

## Overview

LLMCommit enhances your Git workflow by automatically generating well-structured, informative commit messages based on your code changes. It uses a specified LLM provider to analyze diffs and produce commit messages that follow best practices.

## Features

- Generate commit messages from staged or unstaged changes
- Support for multiple AI providers (Ollama and Gemini)
- Customizable configuration
- Add context to guide the AI's analysis
- Simple, intuitive PowerShell interface

## Why LLMCommit?

This project provides a simple means of enhancing commit messages using language models. Ollama and Gemini were chosen for their economic advantages:

- **Ollama**: Run locally on moderate PC hardware with no usage costs
- **Gemini**: Google's generous free tier makes this accessible to everyone

## Installation

```powershell
# Clone the repository
git clone https://github.com/coryb-xyz/LLMCommit.git

# Import the module (for testing)
Import-Module ./LLMCommit -Force

# Or install permanently to your modules folder
Copy-Item -Path ./LLMCommit -Destination "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse
```

## Configuration

On first use, LLMCommit creates a `.llmconfig.json` file in your home directory. Configure it with:

```powershell
Update-LLMConfig -Setting DefaultProvider -Value "Ollama"
Update-LLMConfig -Setting OllamaEndpoint -Value "http://localhost:11434/api/chat"
```

## Usage

```powershell
# Generate commit message from staged changes
New-LLMCommitMessage

# Use an alias (both work the same)
gptcommit
geminicommit

# Include unstaged changes
New-LLMCommitMessage -StagedOnly:$false

# Specify provider and model
New-LLMCommitMessage -LLMProvider Gemini -Model "gemini-2.0-flash"

# Add context to guide the AI
New-LLMCommitMessage -Context "Fix authentication bug in login flow"

# Pipe to git commit
$msg = New-LLMCommitMessage
git commit -m $msg
```

## Module Structure

- **LLMCommit.psm1**: Main module file that loads all functions
- **LLMCommit.psd1**: Module manifest with metadata and exports
- **default-llm-config.json**: Default configuration template

### Public Functions

- **New-LLMCommitMessage**: Core function that generates commit messages
- **Update-LLMConfig**: Manages the module configuration
- **Invoke-OllamaAIGenAPI**: Interfaces with the Ollama API
- **Invoke-GeminiAIGenAPI**: Interfaces with the Google Gemini API

## Requirements

- PowerShell Core 7.0 or higher
- Git command-line tools
- For Ollama: Local Ollama installation
- For Gemini: Google API key (stored securely via SecretManagement as `GeminiApiKey`)

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.