### Setup the environment

Clone the repository and run all scripts.
```
cd $HOME
tdnf install -y git
git clone https://github.com/dcasota/photonos-scripts
cd $HOME/photonos-scripts/docsystem
chmod a+x ./*.sh
./installer.sh
./Ollama-installer.sh
./CodingAI-installers.sh
./Droid-configurator.sh
cd $HOME/photonos-scripts/docsystem/FactoryAI/.factory
```

### Triggering the Swarm  

Run in Droid CLI:
```
droid /run-docs-lecturer-swarm
```


Options:  
  - script for automation
  ```
  #!/bin/bash
  droid --auto-run --spec "Full docs maintenance swarm on $(date)"
  ```
  
  - or create a command
  ```
  # .factory/commands/run-docs-lecturer-swarm.md
  @docs-lecturer-orchestrator Start full docs lecture on https://docs.example.com
  ```
