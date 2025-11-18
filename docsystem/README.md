# Docsystem: A 24/7 Continuous Improvement System for the VMware By Broadcom Photon OS Documentation

## Status Quo

The Photon OS team consists of Broadcom engineers who primarily focus on closed-source projects within the VMware Division, innovating appliances for VMware Cloud Foundation. Most core appliances utilize a closed-source version of Photon OS.

The open-source version of Photon OS is also maintained publicly by the Photon OS team. It supports various computing environments, including multiple CPU architectures, flavors, cloud platforms, generic and hypervisor-optimized configurations, hardened setups, IPv4/IPv6 networking, offline/air-gapped deployments, and live kernel patching. The official Photon OS documentation is available at [https://vmware.github.io/photon](https://vmware.github.io/photon).

From 2015 to 2020, automation and documentation were key priorities. However, after 2020, maintaining up-to-date documentation became increasingly time-consuming, resulting in neglected chapters.

## Challenge

The Photon OS team could delegate more documentation activities to an autonomous AI agent team. The list of potential enhancements is extensive:

- **Integrated AI Chatbot**: Enables users to ask questions or request summaries of documentation content.
- **Scientific Wording**: Emphasized to maintain branch-(release)specific precision and clarity in technical descriptions
- **Grammar Checks**: Automatically applied to produce polished and error-free documentation.
- **Multilanguage Support**: Allows for seamless translation and adaptation across various languages.
- **Embedded Code Sandbox**: Provides a secure environment for testing and demonstrating code snippets within documentation.
- **Changelog Blog Entries**: Automatically generated to track updates and version histories.
- **Static Site Generator Flexibility**: Enables easy switching between tools like Hugo, MkDocs, and Docusaurus for simplified deployment and customization.
- **Learn Academy**: Comprehensive learn modules and quizzes.

## Concept

The strategy for introducing Docsystem encompasses four key phases: **Quality** → **Modernize** → **Globalize** → **Publish**.

### Quality Phase
**Goal**: Enhance the precision, reliability, and professionalism of documentation through rigorous standards and safeguards.

- Emphasizes scientific wording to maintain precision and clarity in technical descriptions.
- Automatically applies grammar checks to produce polished and error-free documentation.
- Incorporates replay safety mechanisms to prevent accidental re-execution of actions or outputs.
- Implements role-based access control (RBAC) to ensure secure permissions and governance across team operations.

### Modernize Phase
**Goal**: Integrate advanced AI-driven tools and flexible infrastructures to automate and streamline documentation processes.

- Establishes a role-based docs writer AI agent team to streamline documentation creation through collaborative AI agents.
- Incorporates AI-powered command-line interfaces (CLIs) for efficient user interactions and automation.
- Leverages system prompts to define specific roles and skills for each AI agent within a team.
- Includes an integrated AI chatbot that enables users to ask questions or request summaries of documentation content.
- Provides an embedded code sandbox for a secure environment to test and demonstrate code snippets within documentation.
- Supports easy switching between static site generators like Hugo, MkDocs, and Docusaurus to simplify deployment and customization.

### Globalize Phase
**Goal**: Expand the accessibility and adaptability of documentation to diverse audiences worldwide.

- Offers multilanguage support for seamless translation and adaptation across various languages.

### Publish Phase
**Goal**: Facilitate consistent tracking and dissemination of updates for effective version management and deployment.

- Automatically generates changelog blog entries to track updates and version histories.



## FactoryAI-centric implementation

In this section, 24/7 docsystem mainly uses FactoryAI's droid features.

### Testing environment

#### Create a self-hosted copy of https://vmware.github.io/photon. 
1. Create a vm with 8gb ram, 4vcpu, 40gb disk.
2. Ensure internet access.
3. Clone docsystem and run `installer.sh`.
```
cd $HOME
tdnf install -y git
git clone https://github.com/dcasota/photonos-scripts
cd $HOME/photonos-scripts/docsystem
chmod a+x ./*.sh
./installer.sh
```

The Photon OS nginx webserver is installed locally. 

#### Prepare the AI tools

Docsystem relies heavily on FactoryAI's Droid CLI. The idea is quite intriguing: an AI agent's objectives and strategies are defined in a markdown file. Multiple agents form a team, and several teams together make up a swarm.
Within the repository, the .factory directory specifies the swarm's goals, as well as each team and its members.

4. run the following commands.
```
./Ollama-installer.sh
./CodingAI-installers.sh
./Droid-configurator.sh
cd $HOME/photonos-scripts/docsystem/.factory
```



`Droid-configurator.sh` installs Droid CLI. This is the initial version, which also provides optional configuration for an external Ollama source and xAI Cloud-LLMs.  

The `Ollama-installer.sh` script is an optional tool for Droid that installs Ollama along with several locally downloaded LLMs. You can check inside the script for instructions on how to enable additional local LLMs.

The `CodingAI-installer.sh` script os an optional tool for Droid that installs a bunch of CLI e.g. FactoryAI Droid CLI, OpenAI Codex CLI, Grok-CLI, Coderabbit CLI, Google Gemini CLI, Anthropic Claude Code, Microsoft Copilot CLI, Cursor CLI, Ampcode CLI,  OpenCode CLI, AllHands CLI, Eigent Multi-Agent. It also installs a n8n Workflow instance, Microsoft Cloudfoundry CLI and Windsurf.



5. Run Droid CLI.
```
droid /run-docs-lecturer-swarm
```



## (Alternatives: Unfinished)

### Docs-Inspector
The script installs docs-inspector daemon. It crawls the local web server and protocols as json files any sort of broken links, markdown issues and english grammar issues.
1. run
   ```
   ./docsinspector.sh
   ```

### Sound configuration
Installs and configures, lobogg, lame, libvorbis, flac, libmad, mpg123, sox, portaudio, sonic, pcaudiolib, and mbrola with various voices for espeak-ng.
1. run
   ```
   ./configuresound.sh
   ```

### Migrate to Docusaurus and mkDocs
Migrates the Photon OS website to docusaurus and Mkdocs.
1. run
   ```
   ./migrate2docusaurus.sh
   ./migrate2mkdocs.sh   
   ```
