# mirror-repository User Manual

## Overview

`mirror-repository.py` is a Python script for mirroring GitHub repositories. It creates an exact copy of a source repository including all branches, tags, and refs to a target GitHub repository. The script handles Git LFS, cleans up non-standard refs (Gerrit, PR refs), and automatically creates the target repository if it doesn't exist.

A legacy Bash version (`mirror-repository.sh`) is also available.

## Usage

### Python Script (Recommended)

```bash
./mirror-repository.py --original-repo <SOURCE_URL> --target-repo <TARGET_URL> [--local-path <PATH>]
```

### Parameters

| Parameter | Short | Required | Description |
|-----------|-------|----------|-------------|
| `--original-repo` | `-o` | Yes | URL of the source GitHub repository to mirror |
| `--target-repo` | `-t` | Yes | URL of the target GitHub repository (mirror destination) |
| `--local-path` | `-l` | No | Local path for the clone (uses temp directory if not specified) |

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_USERNAME` | Yes | Your GitHub username |
| `GITHUB_TOKEN` | Yes | GitHub personal access token with repo permissions |

### Examples

```bash
# Basic mirror operation
./mirror-repository.py \
  --original-repo https://github.com/vmware/photon \
  --target-repo https://github.com/myuser/photon-mirror

# Mirror with custom local clone path
./mirror-repository.py \
  --original-repo https://github.com/vmware/photon \
  --target-repo https://github.com/myuser/photon-mirror \
  --local-path /tmp/photon-clone

# Using short flags
./mirror-repository.py \
  -o https://github.com/vmware/photon \
  -t https://github.com/myuser/photon-mirror \
  -l /tmp/photon-clone
```

## Legacy Bash Script

```bash
./mirror-repository.sh <ORIGINAL_REPO> <REPO_NAME> [LOCAL_PATH]
```

### Bash Script Parameters

| Position | Required | Description |
|----------|----------|-------------|
| 1 | Yes | Source repository URL |
| 2 | Yes | Target repository name (not full URL) |
| 3 | No | Local path for the clone |

### Bash Script Example

```bash
./mirror-repository.sh https://github.com/vmware/photon photon-mirror /tmp/photon-clone
```

**Note**: The Bash script uses `GITHUB_USERNAME` to construct the target URL as `github.com/$GITHUB_USERNAME/$REPO_NAME`.

## What Gets Mirrored

The script performs a complete mirror including:

| Content | Description |
|---------|-------------|
| **All Branches** | Every branch from the source repository |
| **All Tags** | Every tag and release |
| **Git LFS Objects** | Large file storage objects (if present) |
| **Commit History** | Complete commit history for all refs |

### Refs That Are Cleaned

To avoid push errors, the following non-standard refs are removed before pushing:

| Ref Pattern | Source | Reason |
|-------------|--------|--------|
| `refs/users/*` | Gerrit | Non-standard Gerrit refs |
| `refs/changes/*` | Gerrit | Gerrit change refs |
| `refs/pull/*` | GitHub | PR refs (causes "deny updating hidden ref" errors) |

## Process Flow

1. **Validation** - Validates GitHub URLs and checks required environment variables
2. **LFS Detection** - Checks if source repository uses Git LFS
3. **Git Configuration** - Sets git user.name and user.email from GITHUB_USERNAME
4. **Target Check** - Verifies target repository exists; creates it if not
5. **Mirror Clone** - Creates a bare mirror clone of the source repository
6. **Ref Cleanup** - Removes non-standard refs (Gerrit, PR refs)
7. **LFS Handling** - Fetches and pushes LFS objects if present
8. **Mirror Push** - Pushes all branches, tags, and refs to target with `--mirror --force`
9. **Summary** - Displays all synchronized branches
10. **Cleanup** - Removes temp directory (or preserves if `--local-path` specified)

## Output

### Successful Mirror

```
Original repository: vmware/photon
Target repository: myuser/photon-mirror
Target repository already exists. Proceeding with mirroring (note: this will overwrite existing content).
Clone directory: /tmp/photon.abc123
Running: git clone --mirror --progress https://github.com/vmware/photon /tmp/photon.abc123
...
Cleaning up non-standard refs...
Running: git push --mirror --force --progress .../myuser/photon-mirror.git
Everything up-to-date

All 17 branches synchronized: 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, common, dev, gh-pages, master, ...

Mirroring complete. The repository has been duplicated to https://github.com/myuser/photon-mirror
Temporary directory cleaned up.
```

### With Local Path Preservation

```
...
Local repository preserved at: /tmp/photon-clone
```

## Git LFS Support

The script automatically detects Git LFS usage by:

1. Checking `.gitattributes` for `filter=lfs` entries via GitHub API
2. Checking the local `config` file for `[lfs]` section after cloning

If LFS is detected:
- Checks if `git-lfs` is installed
- **Auto-installs `git-lfs` if running as root** (using `tdnf install -y git-lfs`)
- If not running as root, displays error with manual install instructions
- Fetches all LFS objects from source
- Pushes all LFS objects to target

### Auto-Install Behavior

| Running as | git-lfs missing | Action |
|------------|-----------------|--------|
| root | Yes | Auto-installs via `tdnf install -y git-lfs` |
| non-root | Yes | Exits with error and install instructions |
| any | No (installed) | Proceeds normally |

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `GITHUB_USERNAME and GITHUB_TOKEN environment variables must be set` | Missing credentials | Export required environment variables |
| `--original-repo must be a valid GitHub repository URL` | Invalid source URL | Use format `https://github.com/owner/repo` |
| `--target-repo must be a valid GitHub repository URL` | Invalid target URL | Use format `https://github.com/owner/repo` |
| `git-lfs is required for this repository but not installed` | Source uses LFS, not running as root | Run as root for auto-install, or manually: `tdnf install -y git-lfs` |
| `Error creating repository` | API failure | Check token permissions (needs `repo` scope) |
| `Error cloning original repository` | Network/access issue | Verify source URL is accessible |
| `Error pushing to mirror repository` | Push failure | Check token permissions and target repo access |

## Token Permissions

Your GitHub personal access token (`GITHUB_TOKEN`) needs the following scopes:

| Scope | Required For |
|-------|--------------|
| `repo` | Full repository access (read/write) |
| `public_repo` | Public repositories only (if not using private repos) |

To create a token:
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic) with `repo` scope
3. Copy and export as `GITHUB_TOKEN`

## System Requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| Python | 3.9+ | For type hints syntax |
| git | 2.0+ | For mirror clone/push |
| git-lfs | Any | Only if source uses LFS (auto-installed when running as root) |
| requests | Any | Python HTTP library |
| Disk Space | Varies | Depends on repository size |
| Network | Required | For clone and push operations |

## Dependencies

### Python Script

```bash
# Python packages
pip install requests

# System packages (Photon OS)
tdnf install git
tdnf install git-lfs  # Optional, auto-installed when running as root if needed
```

### Bash Script

```bash
# System packages
tdnf install git curl
tdnf install git-lfs  # Optional, auto-installed when running as root if needed
```

## Scheduling Regular Syncs

To keep a mirror up-to-date, schedule the script with cron:

```bash
# Edit crontab
crontab -e

# Add daily sync at 2 AM
0 2 * * * GITHUB_USERNAME=myuser GITHUB_TOKEN=ghp_xxx /path/to/mirror-repository.py -o https://github.com/vmware/photon -t https://github.com/myuser/photon-mirror >> /var/log/mirror-sync.log 2>&1
```

## Comparison: Python vs Bash

| Feature | Python | Bash |
|---------|--------|------|
| Named parameters | Yes (`--original-repo`) | No (positional only) |
| Target URL format | Full URL | Repo name only |
| Branch summary | Yes | No |
| Force push | Yes | No |
| Error handling | Comprehensive | Basic |
| LFS support | Yes | Yes |
| Auto-install git-lfs | Yes (as root) | Yes (as root) |

## Troubleshooting

### Check Environment Variables

```bash
echo "Username: ${GITHUB_USERNAME:-NOT SET}"
echo "Token: ${GITHUB_TOKEN:+SET}${GITHUB_TOKEN:-NOT SET}"
```

### Test GitHub API Access

```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user | grep login
```

### Verify Source Repository Access

```bash
git ls-remote --heads https://github.com/vmware/photon | head -5
```

### Check Target Repository

```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$GITHUB_USERNAME/photon-mirror | grep full_name
```

### Manual Mirror (Debug)

```bash
# Clone
git clone --mirror https://github.com/vmware/photon /tmp/photon-debug

# Check refs
cd /tmp/photon-debug
git for-each-ref --format='%(refname:short)' refs/heads

# Push manually
git push --mirror --force https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/photon-mirror.git
```
