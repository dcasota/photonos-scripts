# Docs Blogger Team

**Purpose**: Automated blog content generation from Photon OS repository commit history and development activities.

## Team Members

### Core Droids
1. **blogger** - Monthly blog post generation from git commit history
2. **pr-bot** - Pull request creation and management for blog content
3. **orchestrator** - Blog content workflow coordination

## Workflow

```
blogger → validation → pr-bot → publication
   ↓
orchestrator (coordination)
```

## Key Responsibilities

- **Repository Analysis**: Clone and analyze vmware/photon repository across all branches
- **Monthly Summaries**: Generate comprehensive monthly development summaries
- **Branch Coverage**: Cover all active branches (3.0, 4.0, 5.0, 6.0, common, master)
- **Technical Analysis**: Deep dive into commits, PRs, security updates, and user impact
- **Content Generation**: Create Hugo-compatible blog posts with proper front matter
- **Production Deployment**: Create pull requests for photon-hugo branch

## Branch Coverage

- **Branch 3.0**: Monthly summaries since 2021
- **Branch 4.0**: Monthly summaries since 2021
- **Branch 5.0**: Monthly summaries since 2021
- **Branch 6.0**: Monthly summaries since 2021
- **Common Branch**: Monthly summaries since 2021
- **Master Branch**: Monthly summaries since 2021

## Quality Requirements

- **Technical Accuracy**: All commit hashes and PR numbers verifiable
- **Comprehensive Coverage**: Every meaningful change documented
- **User Focus**: Changes explained from user perspective
- **Actionable Content**: Clear recommendations provided
- **Hugo Integration**: Proper front matter and URL structure

## Execution Modes

### Live Testing Mode
- Operates on 127.0.0.1 local test system
- Validates content before production
- Safe environment for quality assessment

### Production Mode
- Targets dcasota/photon repository (photon-hugo branch)
- Creates pull requests for integration
- Publishes live user-facing content

## Success Criteria

- **100% Branch Coverage**: All 6 branches documented
- **100% Month Coverage**: No missing months from 2021-present
- **Verified Accuracy**: All technical references verifiable
- **User Comprehension**: Technical complexity explained clearly
- **Production Integration**: Seamless Hugo deployment

## Usage

Trigger the blogger team orchestrator:
```bash
factory run @docs-blogger-orchestrator
```

Or individual droids:
```bash
factory run @docs-blogger-blogger
factory run @docs-blogger-pr-bot
```
