# Implement Task Prompt

Use this prompt with the `c-implementer` droid:

```
Implement task {TASK_NUMBER} from specs/tasks/{TASK_FILE}.

Context:
- Read the task spec for requirements and acceptance criteria
- Read the related FRD from specs/features/
- Read all ADRs from specs/adr/, especially 0004-security-hardening.md
- Follow existing code patterns in src/

Deliver:
- Implementation in src/
- Update specs/tasks/README.md status
- Update .github/CHANGELOG.md
```
