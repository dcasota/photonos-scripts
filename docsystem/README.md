# Photon OS Documentation System (docsystem)

## Overview

The docsystem directory contains comprehensive tools and automation for managing, improving, and publishing Photon OS documentation. It includes installers for documentation platforms, quality assessment tools, migration utilities, and a complete multi-team AI-powered documentation swarm system.

## Quick Start

### Setup Environment

```bash
cd $HOME
tdnf install -y git
git clone https://github.com/dcasota/photonos-scripts
cd $HOME/photonos-scripts/docsystem
chmod a+x ./*.sh
```

### Basic Installation

```bash
# Install Photon OS documentation site (Hugo-based)
./installer.sh

# Install Ollama with LLM models
./Ollama-installer.sh

# Install AI coding assistants
./CodingAI-installers.sh

# Configure Factory AI Droid
./Droid-configurator.sh
```

## Directory Structure

```
docsystem/
├── tools/                           # Documentation tools and utilities
│   ├── Ollama-installer/           # LLM server installation
│   ├── CodingAI-installers/        # AI coding assistants
│   ├── installer-for-self-hosted-Photon-OS-documentation/
│   │   └── installer.sh            # Hugo-based documentation site installer
│   ├── Migrate2Docusaurus/         # Docusaurus migration tools
│   ├── Migrate2MkDocs/             # MkDocs migration tools
│   ├── mirror-repository/          # GitHub repository mirroring
│   ├── weblinkchecker/             # Website link validation
│   ├── configuresound/             # Audio stack installation
│   └── photonos-docs-lecturer/     # Documentation quality analysis
│       ├── photonos-docs-lecturer.py  # Main analysis tool
│       └── plugins/                # Modular detection/fix plugins
├── .factory/                        # Factory AI Droid configuration
│   ├── AGENTS.md                   # Swarm configuration
│   ├── teams/                      # Documentation team droids
│   │   ├── docs-maintenance/       # Quality & content fixes
│   │   ├── docs-sandbox/           # Code block modernization
│   │   ├── docs-translator/        # Multi-language translation
│   │   ├── docs-blogger/           # Automated blog generation
│   │   └── docs-security/          # MITRE ATLAS compliance
│   └── README.md                   # Factory system setup
├── Droid-configurator.sh           # Factory AI Droid setup script
└── README.md                       # This file
```

## Tools Overview

### Documentation Site Installers

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **installer.sh** | Hugo-based documentation site | Self-hosted, HTTPS, comprehensive link fixes |
| **Migrate2Docusaurus** | Docusaurus 3.9.2 migration | Version management, modern UI, blog support |
| **Migrate2MkDocs** | MkDocs Material migration | Multi-version, responsive design, search |

### Quality & Analysis Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **photonos-docs-lecturer** | Documentation quality analysis | Grammar/spelling, markdown validation, automated fixes |
| **weblinkchecker** | Link validation | Recursive crawling, broken link detection, redirect analysis |

### LLM & AI Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **Ollama-installer** | Local LLM server | Context-aware models, OpenAI-compatible API |
| **CodingAI-installers** | AI coding assistants | Factory Droid, Copilot, Claude, Gemini, Grok |

### Infrastructure Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **mirror-repository** | GitHub repository mirroring | Full history, LFS support, auto-sync |
| **configuresound** | Audio stack setup | TTS engines, audio codecs, speech synthesis |

## Documentation Lecturer Plugin System

Version 3.0 introduces a modular plugin architecture for documentation analysis:

### Automatic Fix Plugins

| Plugin | FIX_ID | Description | LLM Required |
|--------|--------|-------------|:------------:|
| broken_email | 1 | Fix broken email addresses | No |
| deprecated_url | 2 | Fix deprecated URLs (VMware, AWS, etc.) | No |
| hardcoded_replaces | 3 | Fix known typos and errors | No |
| heading_hierarchy | 4 | Fix heading hierarchy violations | No |
| header_spacing | 5 | Fix markdown headers missing space | No |
| html_comments | 6 | Fix HTML comments | No |
| vmware_spelling | 7 | Fix VMware spelling | No |
| backticks | 8 | Fix backtick issues | Yes |
| grammar | 9 | Fix grammar and spelling | Yes |
| markdown_artifacts | 10 | Fix unrendered markdown | Yes |
| indentation | 11 | Fix indentation issues | Yes |
| numbered_lists | 12 | Fix numbered list sequences | No |

### Detection-Only Plugins

- **orphan_link** - Broken hyperlinks
- **orphan_image** - Missing images
- **orphan_page** - Unreferenced pages
- **image_alignment** - Image positioning issues

### Usage Examples

```bash
# Analyze documentation (report only)
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5 \
  --parallel 10

# Full workflow with automated fixes and PR
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-repotoken ghp_xxxxxxxxx \
  --gh-username myuser \
  --ghrepo-url https://github.com/myuser/photon.git \
  --ghrepo-branch photon-hugo \
  --gh-pr \
  --parallel 10

# Selective fixes (non-LLM only)
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 1-7,12
```

## Factory AI Droid Swarm System

A five-team documentation system for comprehensive Photon OS documentation processing:

### Team Structure

1. **Docs Maintenance** - Content quality, grammar, links, orphaned pages
   - crawler, auditor, editor, pr-bot, logger

2. **Docs Sandbox** - Code block modernization and interactive runtime
   - crawler, converter, tester, pr-bot, logger

3. **Docs Translator** - Multi-language support (6 languages × 4 versions)
   - translator-german, translator-french, translator-italian, translator-bulgarian, translator-hindi, translator-chinese, chatbot

4. **Docs Blogger** - Automated blog generation from git history
   - blogger, pr-bot

5. **Docs Security** - MITRE ATLAS compliance and security monitoring
   - monitor, atlas-compliance, threat-analyzer, audit-logger

### Execution Flow

```
MASTER ORCHESTRATOR
   ↓
Security Team (continuous monitoring) ←─┐
   ↓                                     │
Maintenance Team → Quality Gates ───────┤
   ↓                                     │
Sandbox Team → Quality Gates ────────────┤
   ↓                                     │
Blogger Team → Quality Gates ────────────┤
   ↓                                     │
Translator Team → Final Validation ──────┘
   ↓
COMPLETE
```

### Running the Swarm

```bash
# Full swarm execution
cd $HOME/photonos-scripts/docsystem/.factory
droid /run-docs-lecturer-swarm

# Individual teams
factory run @docs-maintenance-orchestrator
factory run @docs-sandbox-orchestrator
factory run @docs-translator-orchestrator
factory run @docs-blogger-orchestrator
factory run @docs-security-orchestrator
```

## Environment Variables

Required for GitHub integration:

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
export GITHUB_USERNAME="your-github-username"
export PHOTON_FORK_REPOSITORY="https://github.com/your-username/photon.git"
```

## Access URLs

After installation:

| Service | URL | Credentials |
|---------|-----|-------------|
| Hugo Documentation | `https://<IP_ADDRESS>/` | None (self-signed cert) |
| Docusaurus Site | `https://<IP_ADDRESS>:8443/` | None (self-signed cert) |
| MkDocs Site | `https://<IP_ADDRESS>:8443/` | None (self-signed cert) |
| Ollama API | `http://localhost:11434` | None |
| n8n Workflow | `http://localhost:5678` | None |

## Log Files

| Component | Log Location |
|-----------|-------------|
| Hugo Site | `/var/log/installer.log` |
| Documentation Lecturer | `report-<datetime>.log` |
| Nginx | `/var/log/nginx/error.log` |
| Factory Droid | `.factory/logs/` |

## Quality Gates

### Maintenance Team
- ✅ Critical issues: 0
- ✅ Grammar: >95%
- ✅ Markdown: 100%
- ✅ Accessibility: WCAG AA
- ✅ Orphaned pages: 0

### Sandbox Team
- ✅ Conversion: 100% eligible blocks
- ✅ Functionality: All sandboxes working
- ✅ Security: Isolated execution

### Translator Team
- ✅ Translation: 100% coverage
- ✅ Knowledge base: Complete

### Blogger Team
- ✅ Blog posts: Monthly coverage complete
- ✅ Technical accuracy: All references verified

### Security Team
- ✅ MITRE ATLAS compliance: 100%
- ✅ Critical security issues: 0
- ✅ Isolation violations: 0

## Support & Documentation

For detailed documentation on each tool, see:

- Hugo Site Installation: `tools/installer-for-self-hosted-Photon-OS-documentation/README.md`
- Documentation Lecturer: `tools/photonos-docs-lecturer/README.md`
- Plugin System: `tools/photonos-docs-lecturer/plugins/README.md`
- Factory Swarm: `.factory/teams/README.md`
- Individual Teams: `.factory/teams/*/README.md`

## Contributing

This is part of the photonos-scripts project. For issues or contributions:
- GitHub: https://github.com/dcasota/photonos-scripts
- Issues: https://github.com/dcasota/photonos-scripts/issues

---

# Legacy Content (Historical Reference)

## What is Photon OS scripts?
This repo contains a bunch of Photon OS related scripts.  
Photon OS is a VMware operating system for open source Linux container host for cloud-native applications. It runs on x86_64 + arm64 processors and on several hyperscaler clouds. See https://vmware.github.io/photon .

## Use Case 1 - Photon OS as platform for hosting forensics tools
"Using the recommendations of the Kernel Self-Protection Project (KSPP), the Photon OS Linux Kernel is secure from the start."
As for any forensic platform, the availability of Photon OS is highly important. The planned EOL schedule has been specified [here]( https://blogs.vmware.com/vsphere/2022/01/photon-1-x-end-of-support-announcement.html).

 The actual Photon OS releases are 1:1 related to Linux kernel releases.
| Linux kernel  |   Photon OS   |
| ------------- | ------------- |
|     4.4       |      1.x      |
|     4.9       |      2.x      |
|     4.19      |      3.x      |
|     5.10      |      4.x      |
|     6.1       |      5.0      |
|     6.12      |     (6.0)     |

6.0 isn't released yet.  
Photon OS supports forensics tools components. As example, it can be configured to read/write different filesystem formats - here some findings:
- https://github.com/dcasota/photonos-scripts/wiki/NTFS-mount-on-Photon-OS
- https://github.com/dcasota/photonos-scripts/wiki/VMFS6-mount-on-Photon-OS

The [Security Advisories](https://github.com/vmware/photon/wiki/Security-Advisories) may give an idea of the necessity of chains of packages to be held safe. It takes time to clearly understand a single mitigation. See some personal progress [here](https://github.com/dcasota/photonos-scripts/wiki/Mitigations-for-CPU-vulnerabilities).

With each Linux kernel update trillions of packages permutations are given, in theory it's slightly less architecture specific. A slice of it reflects in Photon OS. You can see which packages are made available from contributors at https://github.com/vmware/photon/commits/dev.

Each package is represented by a spec file and it contains manufacturer information e.g. the original download url Source0. 
Unfortunately, more than half of Source0 url health checks fail because of an old or misspelled url value in the spec file.
To achieve a higher url health ratio, the Source0 url value has been analyzed, and a spec-file-to-Source0-url-lookup has been implemented as part of a script. For analyzing purposes, the script output file per Photon OS version can be imported as spreadsheet. The comma delimited .prn output file contains spec file name, the Source0 original value, the corrected Source0 url after research, the url health check value (200=ok), and an "UpdateAvailable" signalisation. With those url corrections, the Source0 url health ratio increased significantly. If it fits the quality goals, it can help to correct the Source0 urls. 
- [url health sample report for Photon OS 3.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-urlhealth-3.0_202302271112.prn)
- [url health sample report for Photon OS 4.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-urlhealth-4.0_202302271122.prn)
- [url health sample report for Photon OS 5.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-urlhealth-5.0_202302271134.prn)

The following powershell script creates the Source0 url health check reports. It must run on a Windows machine with installed Powershell.
https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report.ps1

In addition, the powershell script creates: 
- [a package report with all packages per Photon OS release version](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report_202302271149.prn)

  ![image](https://user-images.githubusercontent.com/14890243/221566691-cb958ea7-e298-4a42-babc-9fd4eec9e12d.png)

- [a difference report of 3.0 packages with a higher version than same 4.0 package](https://github.com/dcasota/photonos-scripts/blob/master/photonos-diff-report-3.0-4.0_202302271149.prn)
- [a difference report of 4.0 packages with a higher version than same 5.0 package](https://github.com/dcasota/photonos-scripts/blob/master/photonos-diff-report-4.0-5.0_202302271149.prn)

Packages work begin with 'there is a version of package x in relation to y, which is not or it is integrated to photon release z only.' There is no handy interoperability lookup of packages release/flavor/architecture like the inter-product viewer in VMware vSphere interoperability guide though.


## Use Case 2 - Baremetal installation / staging
Baremetal environments are technically supported. The focus of Photon OS however isn't primarily to run on baremetal. For security purposes, peripheral devices connectivity is restricted. But you can install Photon OS on any x86_64 and arm64 baremetal.

On x86_64, Photon OS comes with different installation flavors: "Security hardened" (minimal), Developer, Real Time, and as Ostree-Host.

Photon OS runs best on vSphere x86_64. It runs kubernetes, docker containers, supports a resource foot print hardened setup, and has a package-based lifecycle management system. The secure appliance (virtual hardware v13) installation is built-in VMware hypervisor optimized, and delivered as OVA setup.

Also, since 5.0 beta, there is more support for running Photon OS on ESXi on Arm.

Provisioning Photon OS on Raspberry Pi is supported as well, e.g. see [Configuring a Raspberry Pi 4 for supporting usb license dongle remoting](https://github.com/dcasota/photonos-scripts/wiki/Configure-a-complete-Raspberry-Pi-Virtualhere-installation).

## Use Case 3 - Azure installation with UEFI boot support
In a Non-vSphere hyperscaler environment - this chapter is Microsoft Azure specific - the following scripts may be helpful when creating a Photon OS virtual machine with UEFI support.
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzImage-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzVM_FromImage-PhotonOS.ps1  
```create-AzImage-PhotonOS.ps1``` creates an Azure Generation V2 image, per default of VMware Photon OS 4.0.  
```create-AzVM_FromImage-PhotonOS.ps1``` provisions on Azure a Photon OS VM with the Azure image created using ```create-AzImage-PhotonOS.ps1```.

## Use Case 4 - PowerCLI on Photon OS
"VMware PowerCLI is a suite of PowerShell modules to manage VMware products and services. VMware PowerCLI includes over 800 cmdlets to easily manage your infrastructure on a global scale." See the [interoperability matrix](https://developer.vmware.com/docs/17472/-compatibility-matrix).
Actually there is no single package for PowerCLI. Powershell must always have already been installed.
There are three different installation options - container-based, photon os built-in and scripted install.

### package installation (tdnf)
You can install the powershell package right before PowerCLI. Photon OS 3.0 and above supports Powershell since release 6.2.

To install or update Powershell Core enter
- ```tdnf install powershell``` or ```tdnf update powershell```

Install or update PowerCLI in a powershell command enter
- ```install-module -name VMware.PowerCLI``` or ```update-module -name VMware.PowerCLI```

### docker installation
VMware PowerCLI is available as docker container. Run
- ```docker pull vmware/powerclicore:latest```
- ```docker run -it vmware/powerclicore:latest```

### scripted install 
In some scenarios it is helpful to have a specific Powershell release. Some PowerCLI cmdlets on Windows do not work yet on Photon OS. Simple as that, many Microsoft Windows-specific lowlevel functions were not or are not cross-compatible.  
In [PwshOnPhotonOS](https://github.com/dcasota/photonos-scripts/tree/master/PwshOnPhotonOS) you find install scripts for Powershell on Photon OS with focus on fulfilling prerequisites for VMware.PowerCLI. Each script ```Pwsh[Release]OnPhotonOS.sh``` deploys the specific Powershell Core release on Photon OS.

Example: Install the Powershell release 7.1.3 using ```Pwsh7.1.3OnPhotonOS.ps1```. Simply enter afterwards ```pwsh7.1.3```.

![Powershell_on_Photon](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/Photon2-pwsh-current.png)

Afterwards you easily can install VMware.PowerCLI with ```install-module VMware.PowerCLI```.

#### PowerCLI runspace per release - workflow based side-by-side installation testing
Side-by-side-installations in nowadays work fine. This wasn't always the case, see Powershell 6.x warnings.
  
![side-side-installation](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/side-side-installation.png).

The idea of developing a testing workflow for side-by-side installation combinations using [VMware Tanzu Community Edition](https://tanzucommunityedition.io/) came up as some sort of basics for 'PowerCLI runspace per release'.  
![Status Oct21](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/Status_Oct21.png)

## Use Case 5 - Learning from Kube Academy
[Kube Academy](https://kube.academy) contains a huge bunch of Kubernetes learning videos. The 'setting up the workstation' has been adopted to run the labs on Photon OS, see
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy---setting-up-the-workstation
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy-Scripts

## Use Case 6 - Docker containers
Docker in most Linux distros has built-in support. Photon OS' architecture strength is the maintenance of all flavors from security-hardened to hardware-optimized. This combination is highly preferred for some container purposes.
See some personal docker container learning progress with [Potree - a WebGL based viewer for large point clouds](https://github.com/dcasota/photonos-scripts/wiki/Configure-Potree,-a-WebGL-based-viewer-for-large-point-clouds,-on-VMware-Photon-OS).

## Use Case 7 - ISO build machine on Photon OS
From a packages update service consistency perspective, there is always a good moment for creating an ISO binary.
Photon OS can be used as ISO build platform. Some personal progress using Photon OS as Photon OS ISO build machine has been documented on [How to build the Photon OS ISO file](https://github.com/dcasota/photonos-scripts/wiki/How-to-build-the-Photon-OS-ISO-file). Photon OS could be used to create eg. Microsoft Windows ISO builds from [uupdump.net](https://uupdump.net) as well.

## Photon OS components in commercial products and open-source Photon OS
From a paid support perspective, open source Photon OS has nothing to do with the VMware commercial products in which some Photon OS components are a customized part of. VCSA, vSphere Replication, Workstation, vRealize Operations, and much more run on a strict VMware governance for that commercial product.

There isn't a customer product SKU Photon Platform 2.x, 3.x or 4.x. Hence you cannot buy official Photon Platform support. 

Before strictly separating commercial components, there was a VMware Photon Platform 1.x. It hit End of General Support on 2019-03-02.
For VMware products' Enterprise Application Policy, see https://www.vmware.com/support/policies/enterprise-application.html.

## Archive

This section contains deprecated scripts and hints. DO NOT USE

```pwshgalleryonphotonos.sh```
This study script makes Microsoft Powershell Core available on Photon OS by using Mono with Nuget.

It uses a tool from the Microsoft open source Nuget ecosystem.
See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org

Keep in mind, that only a small set of modules on powershellgallery work on Linux. On MS Windows, Powershell provides a module NetSecurity which isn't made available on Linux, even not with Powershell 7. Hence, cmdlets like ```Test-Netconnection``` are missing.

The tool called nuget.exe is Windowsx86-commandline-only and is used to support more lowlevel compatibility. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
"The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides ALL NUGET CAPABILITIES;"
"it can also be run on Mac OSX and Linux using Mono with some limitations."

The script downloads all necessary prerequisites (tools, Mono, Nuget.exe) and builds the Mono software. It installs
- Photon OS updates
- Mono, an open source implementation of Microsoft's .NET Framework https://www.mono-project.com/
- Nuget, a Microsoft .NET foundation Windows x86 package manager CLI https://www.nuget.org/
- Source packageproviders registration (nuget, powershellgallery)
- Windows Packagemanagement (formerly OneGet) and Powershellget, a package management provider based on NuGet provider https://github.com/PowerShell/PowerShellGet/releases
- Windows PowershellCore by Photon OS package provider tdnf

The PowershellGallery registration is the oneliner:
```mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"```

The Microsoft Powershell installation is processed in reference to https://github.com/vmware/powerclicore/blob/master/Dockerfile.

Don't wonder - the full installation takes quite some time. As the Mono installation consumes fifty minutes and more (!) and usually you don't need a full Mono development environment, it became more a learn project. If interested, see files Findings_*.

You can setup nuget.exe with github actions: https://github.com/marketplace/actions/setup-nuget-exe-for-use-with-actions

```Dockerfile```
This Docker image contains Powershell Core 7.0.0 (Beta4) with registered Powershell Gallery.
The Docker image uses Mono with nuget.exe on a Debian OS.
- The mono 6.4.0.198 dockerfile related part original is from https://github.com/mono/docker/blob/master/6.4.0.198/Dockerfile.
- The original installation procedure for Pwsh7 on Linux is from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7

Simply build and run:
- ```cd /yourpathtoDockerfile/```
- ```docker run -it $(docker build -q .)```
