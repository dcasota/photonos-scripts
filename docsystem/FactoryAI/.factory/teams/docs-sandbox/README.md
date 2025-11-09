# Docs Sandbox Team

**Purpose**: Code block modernization and interactive runtime integration.

## Team Members

### Core Droids
1. **sandbox-converter** - Convert code blocks to interactive sandboxes
2. **tester** - Test and verify sandbox functionality

## Workflow

```
sandbox-converter → tester
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
factory run @docs-sandbox-converter
factory run @docs-sandbox-tester
```
