# Docs Translator Team

**Purpose**: Multi-language content preparation and knowledge base integration.

## Team Members

### Core Droids
1. **translator** - Multi-language translation and preparation
2. **blogger** - Blog content generation from documentation
3. **chatbot** - Knowledge base population for interactive assistance

## Workflow

```
translator → blogger
     ↓
  chatbot (knowledge indexing)
```

## Key Responsibilities

- **Translation**: Prepare content for multiple languages
- **Blog Generation**: Create blog posts from documentation
- **Knowledge Base**: Structure content for chatbot integration
- **Content Structuring**: Organize translated content

## Supported Languages

- English (USA)
- French
- German
- Spanish
- Italian
- Hindi (India)
- Mandarin Chinese (China)

## Quality Gates

- Translation Coverage: 100% of source content
- Blog Posts: Minimum 5 posts from processed content
- Knowledge Base: Complete content indexing
- Content Structure: Proper organization for Hugo multilang

## Usage

Trigger the translator team orchestrator:
```bash
factory run @docs-translator-orchestrator
```

Or individual droids:
```bash
factory run @docs-translator-translator
factory run @docs-translator-blogger
factory run @docs-translator-chatbot
```
