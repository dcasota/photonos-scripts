# Docs Sandbox Team

**Purpose**: Code block modernization and interactive runtime integration.

## Team Members

### Core Droids
1. **crawler** - Site discovery and code block identification
2. **converter** - Convert code blocks to interactive sandboxes
3. **tester** - Test and verify sandbox functionality
4. **pr-bot** - Pull request creation and management
5. **logger** - Session logging and progress tracking

## Workflow

```
crawler → converter → tester → pr-bot
   ↓
logger (continuous)

[Security monitoring by Team 5: Docs Security]
```

## Key Responsibilities

- **Code Block Identification**: Find all code blocks in documentation
- **Sandbox Integration**: Implement @anthropic-ai/sandbox-runtime
- **Interactive Elements**: Create executable code examples
- **Testing & Verification**: Ensure all sandboxes work correctly
- **Safe Execution**: Isolated environment validation

## Conversion Levels

- **Low**: Major code blocks only (tutorials, key examples)
- **Medium**: All code blocks
- **High**: All code blocks + advanced interactive features

## Quality Gates

- Sandbox Conversion: 100% of eligible code blocks
- Functionality: All sandboxes execute successfully
- Isolation: Safe execution environment validated

## Usage

Trigger the sandbox team orchestrator:
```bash
factory run @docs-sandbox-orchestrator
```

Or individual droids:
```bash
factory run @docs-sandbox-crawler
factory run @docs-sandbox-converter
factory run @docs-sandbox-tester
factory run @docs-sandbox-pr-bot
factory run @docs-sandbox-logger
```

## Security Monitoring

This team is monitored by **Team 5: Docs Security** for:
- Sandbox isolation enforcement
- Code injection prevention
- Resource limit validation
- Escape attempt detection
- MITRE ATLAS compliance
