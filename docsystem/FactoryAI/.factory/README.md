### Triggering the Swarm  
Create a command:
```
# .factory/commands/run-docs-lecturer-swarm.md
@docs-lecturer-orchestrator Start full docs lecture on https://docs.example.com
```

Run in Droid CLI:
```
droid /run-docs-lecturer-swarm
```
Or script for automation:
```
#!/bin/bash
cd /path/to/docs-repo
droid --auto-run --spec "Full docs maintenance swarm on $(date)"
```
