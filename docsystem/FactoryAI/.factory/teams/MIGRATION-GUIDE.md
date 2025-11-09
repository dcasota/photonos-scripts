# Migration Guide: Old Structure → New Three-Team Structure

## Overview

This guide explains the migration from the complex 15+ droid structure to the simplified three-team organization.

## Structure Comparison

### Old Structure (.factory/droids/)
```
droids/
├── orchestrator.md (complex, 1000+ lines)
├── docs-lecturer-crawler.md
├── docs-lecturer-auditor.md
├── docs-lecturer-editor.md
├── docs-lecturer-pr-bot.md
├── docs-lecturer-logger.md
├── docs-lecturer-security.md
├── docs-lecturer-sandbox.md
├── docs-lecturer-tester.md
├── docs-lecturer-translator.md
├── docs-lecturer-blogger.md
├── docs-lecturer-chatbot.md
└── [and more...]
```

### New Structure (.factory/teams/)
```
teams/
├── MASTER-ORCHESTRATOR.md (simplified coordination)
├── README.md (documentation)
├── MIGRATION-GUIDE.md (this file)
│
├── docs-maintenance/
│   ├── README.md
│   ├── orchestrator.md
│   ├── crawler.md
│   ├── auditor.md
│   ├── editor.md
│   ├── pr-bot.md
│   ├── logger.md
│   └── security.md
│
├── docs-sandbox/
│   ├── README.md
│   ├── orchestrator.md
│   ├── converter.md
│   └── tester.md
│
└── docs-translator/
    ├── README.md
    ├── orchestrator.md
    ├── translator.md
    ├── blogger.md
    └── chatbot.md
```

## Droid Mapping

### Team 1: Docs Maintenance
| Old Droid | New Location | Changes |
|-----------|--------------|---------|
| docs-lecturer-crawler.md | docs-maintenance/crawler.md | Simplified, focused on core crawling |
| docs-lecturer-auditor.md | docs-maintenance/auditor.md | Streamlined quality checks |
| docs-lecturer-editor.md | docs-maintenance/editor.md | Cleaner fix implementation |
| docs-lecturer-pr-bot.md | docs-maintenance/pr-bot.md | Simplified PR workflow |
| docs-lecturer-logger.md | docs-maintenance/logger.md | Focused logging |
| docs-lecturer-security.md | docs-maintenance/security.md | Core security checks |

### Team 2: Docs Sandbox
| Old Droid | New Location | Changes |
|-----------|--------------|---------|
| docs-lecturer-sandbox.md | docs-sandbox/converter.md | Focused on conversion only |
| docs-lecturer-tester.md | docs-sandbox/tester.md | Dedicated to sandbox testing |

### Team 3: Docs Translator
| Old Droid | New Location | Changes |
|-----------|--------------|---------|
| docs-lecturer-translator.md | docs-translator/translator.md | Simplified translation flow |
| docs-lecturer-blogger.md | docs-translator/blogger.md | Focused blog generation |
| docs-lecturer-chatbot.md | docs-translator/chatbot.md | Knowledge base only |

## Key Simplifications

### 1. Orchestrator Complexity Reduced
**Old**: Single 1000+ line orchestrator managing all droids
**New**: Master orchestrator + 3 team orchestrators (each 100-200 lines)

**Benefits**:
- Easier to understand and maintain
- Clear team boundaries
- Isolated failure domains
- Better debugging

### 2. Removed Redundant Droids
**Removed/Consolidated**:
- `photon-multi-language-preparation.md` → Merged into translator.md
- `run-docs-lecturer-swarm.md` → Replaced by MASTER-ORCHESTRATOR.md
- `docs-lecture-swarm-orchestrator.md` → Replaced by team orchestrators

### 3. Clearer Execution Flow
**Old Flow**:
```
orchestrator → delegate to 15 droids → complex interdependencies
```

**New Flow**:
```
master → maintenance team (6 droids)
      → sandbox team (2 droids)
      → translator team (3 droids)
```

### 4. Simplified Configuration
**Old**: Complex auto-level rules scattered across droids
**New**: Consistent auto-level configuration per team

## Migration Steps

### For Users

1. **Update references**:
   ```bash
   # Old way
   factory run @orchestrator
   
   # New way
   factory run @DocsSwarmMasterOrchestrator
   ```

2. **Team-specific execution**:
   ```bash
   # Run only maintenance
   factory run @docs-maintenance-orchestrator
   
   # Run only sandbox
   factory run @docs-sandbox-orchestrator
   
   # Run only translator
   factory run @docs-translator-orchestrator
   ```

3. **Individual droid access**:
   ```bash
   # Old way
   factory run @docs-lecturer-crawler
   
   # New way
   factory run @docs-maintenance-crawler
   ```

### For Developers

1. **Update droid names in scripts**:
   ```yaml
   # Old
   delegate_to_droid: "@docs-lecturer-crawler"
   
   # New
   delegate_to_droid: "@docs-maintenance-crawler"
   ```

2. **Update file paths**:
   ```bash
   # Old
   .factory/droids/docs-lecturer-crawler.md
   
   # New
   .factory/teams/docs-maintenance/crawler.md
   ```

3. **Update orchestrator references**:
   ```yaml
   # Old
   delegate_to_droid: "@orchestrator"
   
   # New
   delegate_to_droid: "@DocsSwarmMasterOrchestrator"
   # Or team-specific:
   delegate_to_droid: "@docs-maintenance-orchestrator"
   ```

## Backward Compatibility

### Option 1: Symlinks (Quick Migration)
```bash
cd .factory/droids
ln -s ../teams/docs-maintenance/crawler.md docs-lecturer-crawler.md
ln -s ../teams/docs-maintenance/auditor.md docs-lecturer-auditor.md
# ... etc for all droids
```

### Option 2: Gradual Migration
1. Keep old structure temporarily
2. Update references gradually
3. Remove old structure after verification

### Option 3: Clean Break (Recommended)
1. Archive old droids directory:
   ```bash
   mv .factory/droids .factory/droids.old
   ```
2. Use new teams structure exclusively
3. Remove archive after validation

## Testing the Migration

### 1. Verify Structure
```bash
cd .factory/teams
ls -la docs-maintenance/
ls -la docs-sandbox/
ls -la docs-translator/
```

### 2. Test Individual Teams
```bash
# Test maintenance team
factory run @docs-maintenance-orchestrator

# Test sandbox team
factory run @docs-sandbox-orchestrator

# Test translator team
factory run @docs-translator-orchestrator
```

### 3. Test Master Orchestrator
```bash
factory run @DocsSwarmMasterOrchestrator
```

### 4. Verify Quality Gates
Check that all quality gates still function:
- Critical issues detection
- Grammar compliance checking
- Markdown validation
- PR creation workflows

## Benefits of New Structure

### ✅ Simplicity
- 3 teams instead of 15+ scattered droids
- Clear team boundaries and responsibilities
- Linear execution flow

### ✅ Maintainability
- Easier to update individual teams
- Isolated failure domains
- Better error handling

### ✅ Scalability
- Easy to add new droids to existing teams
- Can extend teams independently
- Clear extension points

### ✅ Performance
- Parallel team execution possible
- Better resource management
- Optimized workflows

### ✅ Documentation
- Each team has README
- Clear usage examples
- Better onboarding for new users

## Troubleshooting

### Issue: "Droid not found"
**Solution**: Update droid name to new team-based naming:
```bash
# Old: @docs-lecturer-crawler
# New: @docs-maintenance-crawler
```

### Issue: "Orchestrator not responding"
**Solution**: Use team-specific orchestrator:
```bash
factory run @docs-maintenance-orchestrator
```

### Issue: "Quality gates not working"
**Solution**: Verify auto-config.json is in place and properly configured.

### Issue: "PRs not being created"
**Solution**: Check that pr-bot is using correct repository:
```yaml
repository: "https://github.com/dcasota/photon"
branch: "photon-hugo"
```

## Rollback Plan

If migration causes issues:

1. **Restore old structure**:
   ```bash
   mv .factory/droids.old .factory/droids
   ```

2. **Use original orchestrator**:
   ```bash
   factory run @orchestrator
   ```

3. **Report issues** for future resolution

## Support and Questions

- Check team-specific README files
- Review MASTER-ORCHESTRATOR.md
- Consult individual droid documentation
- Check logs in respective team directories

## Next Steps

After successful migration:

1. ✅ Verify all teams functional
2. ✅ Update any external scripts
3. ✅ Train team members on new structure
4. ✅ Archive old structure
5. ✅ Document any custom modifications

## Conclusion

The new three-team structure provides:
- **Better organization** through clear team boundaries
- **Easier maintenance** through simplified workflows
- **Improved reliability** through isolated failure domains
- **Better scalability** through modular team design

Migration should be straightforward with this guide. The new structure maintains all original functionality while providing significant improvements in clarity and maintainability.
