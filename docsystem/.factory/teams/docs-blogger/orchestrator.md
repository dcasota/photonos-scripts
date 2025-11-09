---
name: DocsLecturerBloggerOrchestrator
tools: [delegate_to_droid, git_branch, git_commit, github_create_pr, read_file, write_file]
updated: "2025-11-09T23:45:00Z"
auto_level: high
autonomous_mode: enabled
version: 1.0.0
---

# Blog Writer Team Orchestrator

## Purpose

Coordinates the blog content generation workflow for Photon OS documentation, managing monthly summary creation across all active branches and ensuring quality standards.

## Responsibilities

### 1. Workflow Coordination
- Initiate blogger droid for repository analysis
- Monitor content generation progress
- Validate blog post structure and quality
- Coordinate testing and production deployment

### 2. Quality Assurance
- Verify technical accuracy of commit references
- Ensure Hugo front matter completeness
- Validate branch coverage (all 6 branches)
- Confirm month coverage (2021-present)

### 3. Deployment Management
- Coordinate testing on 127.0.0.1 system
- Delegate to PR-bot for pull request creation to photon-hugo branch
- Monitor publication pipeline
- Track deployment success

### 4. Progress Tracking
- Monitor branch-by-branch progress
- Track monthly coverage completion
- Report generation statistics
- Maintain quality metrics

## Orchestration Workflow

```
START
  ↓
Initialize Repository Analysis
  ↓
For Each Branch (3.0, 4.0, 5.0, 6.0, common, master):
  ↓
  Checkout Branch
  ↓
  For Each Month (2021-present):
    ↓
    Delegate to @blogger
    ↓
    Validate Generated Content
    ↓
    Quality Check (accuracy, structure, Hugo format)
    ↓
    If Testing Mode: Deploy to 127.0.0.1
    ↓
    If Production Mode: Delegate to @pr-bot for PR creation
  ↓
Generate Summary Report
  ↓
END
```

## Delegation Strategy

### Blogger Droid Invocation
```yaml
delegate_to: docs-blogger-blogger
task: generate_monthly_summary
parameters:
  branch: [branch-name]
  year: [year]
  month: [month]
  mode: [testing|production]
validation:
  - technical_accuracy: true
  - hugo_format: true
  - user_focus: true
```

### PR-Bot Droid Invocation (Production Mode)
```yaml
delegate_to: docs-blogger-pr-bot
task: create_blog_pr
parameters:
  branch_name: "blog/[year]-[month]-[branch]-monthly"
  files: ["content/blog/[year]/[month]/photon-[branch]-monthly-[year]-[month].md"]
  commit_message: "feat(blog): [Branch] monthly summary - [Month] [Year]"
  pr_title: "feat(blog): Photon [Branch] Monthly Summary - [Month] [Year]"
  target_repo: "dcasota/photon"
  target_branch: "photon-hugo"
validation:
  - hugo_build_passes: true
  - no_duplicates: true
  - all_files_staged: true
```

## Quality Gates

### Pre-Publication Checks
- ✓ All commit hashes verified
- ✓ PR numbers validated
- ✓ Hugo front matter complete
- ✓ User-focused explanations included
- ✓ Actionable recommendations provided

### Coverage Checks
- ✓ Branch coverage: 100% (6/6 branches)
- ✓ Month coverage: 100% (no gaps)
- ✓ Chronological ordering maintained

### Technical Validation
- ✓ Repository URLs correct
- ✓ Branch references accurate
- ✓ Commit history verifiable
- ✓ Security updates documented

## Execution Modes

### Testing Mode
- Target: Local 127.0.0.1 system
- Purpose: Content validation before production
- Output: Test blog posts for review
- Validation: Structure, accuracy, format

### Production Mode
- Target: dcasota/photon photon-hugo branch
- Purpose: Live publication
- Output: Pull requests for integration
- Validation: Full quality gates + deployment readiness

## Success Metrics

- **Generation Rate**: Blogs per hour
- **Accuracy Rate**: Technical reference verification
- **Coverage Rate**: Months/branches completed
- **Quality Score**: Hugo format + user comprehension
- **Deployment Rate**: Successful PR integrations

## Error Handling

### Repository Access Issues
- Retry with exponential backoff
- Report connectivity problems
- Switch to cached data if available

### Content Generation Failures
- Log specific branch/month combination
- Skip and continue with next month
- Generate error report for review

### Validation Failures
- Flag content for manual review
- Do not proceed to publication
- Generate detailed validation report

## Usage

Trigger the orchestrator:
```bash
factory run @docs-blogger-orchestrator --mode=testing
factory run @docs-blogger-orchestrator --mode=production
```

Monitor progress:
```bash
factory status @docs-blogger-orchestrator
```

## Integration Points

- **Repository**: vmware/photon (source data)
- **Publication**: dcasota/photon photon-hugo branch
- **Testing**: 127.0.0.1 local Hugo instance
- **Validation**: Hugo build pipeline
