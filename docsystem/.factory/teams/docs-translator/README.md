# Docs Translator Team

**Purpose**: Multi-language translation for Photon OS documentation across all versions.

**IMPORTANT**: This team processes AFTER all other teams (Maintenance, Sandbox, Blogger) have completed.

## Team Members

### Language-Specific Translation Droids
1. **translator-german** - German translation (versions 3.0, 4.0, 5.0, 6.0)
2. **translator-french** - French translation (versions 3.0, 4.0, 5.0, 6.0)
3. **translator-italian** - Italian translation (versions 3.0, 4.0, 5.0, 6.0)
4. **translator-bulgarian** - Bulgarian translation (versions 3.0, 4.0, 5.0, 6.0)
5. **translator-hindi** - Hindi translation (versions 3.0, 4.0, 5.0, 6.0)
6. **translator-chinese** - Simplified Chinese translation (versions 3.0, 4.0, 5.0, 6.0)

### Integration Droids
7. **chatbot** - Knowledge base population for interactive assistance

## Workflow

```
[Wait for all other teams to complete]
  ↓
translator-german   ┐
translator-french   │
translator-italian  ├─ (Parallel processing)
translator-bulgarian│
translator-hindi    │
translator-chinese  ┘
  ↓
chatbot (indexes all languages)
  ↓
PR creation
```

## Key Responsibilities

- **Multi-Language Translation**: Complete translations for 6 languages
- **Version Coverage**: Translate all Photon OS versions (3.0, 4.0, 5.0, 6.0)
- **Technical Accuracy**: Preserve technical terms and command syntax
- **Knowledge Base**: Index multilingual content for chatbot
- **Quality Assurance**: Native language quality review for each language

## Target Languages

- **German (de-DE)**: German-speaking Europe
- **French (fr-FR)**: French-speaking regions
- **Italian (it-IT)**: Italian-speaking regions  
- **Bulgarian (bg-BG)**: Bulgarian and Cyrillic regions
- **Hindi (hi-IN)**: Hindi-speaking India
- **Simplified Chinese (zh-CN)**: China and Chinese-speaking regions

## Version Coverage

Each language droid translates:
- Photon OS 3.0 complete documentation
- Photon OS 4.0 complete documentation
- Photon OS 5.0 complete documentation
- Photon OS 6.0 complete documentation

## Quality Gates

- Translation: 100% content coverage for all versions
- Language Quality: Native speaker review for each language
- Technical Accuracy: Commands and code blocks preserved
- Knowledge Base: Complete multilingual indexing
- Formatting: Markdown structure maintained across all languages

## Execution Order

**CRITICAL**: This team must run AFTER:
1. Maintenance team (content quality fixed)
2. Sandbox team (code blocks modernized)
3. Blogger team (blog content generated)

Only translate finalized, quality-checked content.

## Usage

Trigger the translator team orchestrator:
```bash
factory run @docs-translator-orchestrator
```

Or individual language droids:
```bash
factory run @docs-translator-german
factory run @docs-translator-french
factory run @docs-translator-italian
factory run @docs-translator-bulgarian
factory run @docs-translator-hindi
factory run @docs-translator-chinese
factory run @docs-translator-chatbot
```
