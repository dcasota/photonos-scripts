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

Docsystem relies heavily on FactoryAI's Droid CLI. The idea is quite intriguing: an AI agent's objectives and strategies are defined in a markdown file. Multiple agents form a team, and several teams together make up a swarm.

In this section, 24/7 docsystem mainly uses FactoryAI's droid features.

### Testing environment

#### Create a self-hosted copy of https://vmware.github.io/photon. 
1. Create a vm with 8gb ram, 4vcpu, 40gb disk.
2. Ensure internet access.
3. Run the following commands to clone the repository.
```
cd $HOME
sudo tdnf install -y git
git clone https://github.com/dcasota/photonos-scripts
cd $HOME/photonos-scripts/docsystem
find . -type f -name "*.sh" -exec sudo chmod +x {} \;
```

Within the repository, the .factory subdirectory specifies the swarm's goals, as well as each team and its members.

4. Optionally, run the tools in tools subdirectory, see README. Here a few examples:
   Create a self-hosted Photon OS documentation website using `./tools/installer-for-self-hosted-Photon-OS-documentation/installer.sh`.
   Improve the Photon OS documentation website content by automated analyis and pull requests using tools/photonos-docs-lecturer. 
   Droid can make use of local LLMs using Ollama and Web-LLMs such as Google Gemini and xAI Grok using tools/Ollama-installer and tools/CodingAI-installers.

6. Configure and run Droid.  

   `Droid-configurator.sh` installs Droid CLI. This is the initial version, which also provides optional configuration for an external Ollama source and xAI Cloud-LLMs.  

```
sudo ./Droid-configurator.sh
cd $HOME/photonos-scripts/docsystem/.factory
sudo droid /run-docs-lecturer-swarm
```


#### Hint: export environment variables in a non-root environment

In a non-root environment, run the following script to save the exported environment variables before starting `./tools/installer-for-self-hosted-Photon-OS-documentation/installer.sh`.
```
#!/bin/bash

# Script to configure sudo to preserve specific environment variables system-wide.
# This adds 'Defaults env_keep += "GITHUB_TOKEN GITHUB_USERNAME PHOTON_FORK_REPOSITORY"' to a file in /etc/sudoers.d/
# WARNING: This modifies system sudo configuration and affects all users with sudo access.
# Run with sudo. Backup /etc/sudoers.d/ before running.

# Check if not run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run with sudo."
    exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/env_keep_custom"
ENV_KEEP_LINE='Defaults env_keep += "GITHUB_TOKEN GITHUB_USERNAME PHOTON_FORK_REPOSITORY"'

# Check if the file exists and if the line is already present
if [ -f "$SUDOERS_FILE" ] && grep -Fxq "$ENV_KEEP_LINE" "$SUDOERS_FILE"; then
    echo "The env_keep configuration for these variables is already present in $SUDOERS_FILE."
else
    # Create or append to the file
    echo "$ENV_KEEP_LINE" > "$SUDOERS_FILE"  # Use > to create/overwrite for simplicity; adjust if needed
    chmod 0440 "$SUDOERS_FILE"  # Set correct permissions
    echo "Added env_keep configuration to $SUDOERS_FILE."
    
    # Validate sudoers syntax
    if ! visudo -c -f "$SUDOERS_FILE"; then
        echo "Error: Invalid sudoers syntax. Reverting changes."
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
fi

echo "Configuration complete. Now, set the variables in your shell (e.g., export GITHUB_TOKEN='your_value'), and they will be preserved in sudo commands."
echo "Test with: sudo printenv GITHUB_TOKEN"
echo "Note: This does not set the variables themselves—only preserves them when already set."
```

#### Hint: mirrored repository for testing purpose

Testing photonos-docs-lecturer on the original Photon OS GitHub repo may expose unfinished public commits. It's more effective to use a separate mirrored repository for testing.

For this, you can use `mirror-repository.py` or `mirror-repository.sh`.
Usage: `./tools/mirror-repository/mirror-repository.sh <ORIGINAL_REPO> <TARGET_REPO> [LOCAL_PATH]`

Example:
```
./tools/mirror-repository/mirror-repository.sh https://github.com/username/photon https://github.com/username/photon-docsystemtesting $HOME
cd $HOME
git clone https://github.com/username/photon-docsystemtesting
```
