#!/bin/bash

# Usage: ./mirror_repo.sh [ORIGINAL_REPO] [REPO_NAME] [LOCAL_PATH]
# If not provided as arguments, falls back to environment variables ORIGINAL_REPO, REPO_NAME, and LOCAL_PATH.
# LOCAL_PATH is optional - if not provided, a temporary directory will be used.
# Required environment variables: GITHUB_USERNAME, GITHUB_TOKEN

# Check for required commands
command -v git >/dev/null 2>&1 || { echo "Error: git is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed."; exit 1; }
command -v mktemp >/dev/null 2>&1 || { echo "Error: mktemp is required but not installed."; exit 1; }
command -v base64 >/dev/null 2>&1 || { echo "Error: base64 is required but not installed."; exit 1; }

# Get parameters
ORIGINAL_REPO=${1:-${ORIGINAL_REPO:-}}
REPO_NAME=${2:-${REPO_NAME:-}}
LOCAL_PATH=${3:-${LOCAL_PATH:-}}

# Check if required parameters are set
if [ -z "$ORIGINAL_REPO" ] || [ -z "$REPO_NAME" ]; then
  echo "Error: ORIGINAL_REPO and REPO_NAME must be provided as arguments or environment variables."
  echo "Usage: $0 <ORIGINAL_REPO> <REPO_NAME> [LOCAL_PATH]"
  exit 1
fi

# Check if required environment variables are set
if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_USERNAME and GITHUB_TOKEN environment variables must be set."
  exit 1
fi

# Extract original owner/repo from ORIGINAL_REPO (assuming https://github.com/owner/repo(.git))
ORIGIN=$(echo "$ORIGINAL_REPO" | sed -E 's|https://github.com/([^/]+)/([^/.]+)(\.git)?|\1/\2|')

if [ "$ORIGIN" = "$ORIGINAL_REPO" ]; then
  echo "Error: ORIGINAL_REPO must be a GitHub repository URL."
  exit 1
fi

# GitHub API base URL
API_BASE="https://api.github.com"

# Function to check if the original repo uses Git LFS
check_lfs() {
  RESPONSE=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "Authorization: token $GITHUB_TOKEN" "$API_BASE/repos/$ORIGIN/contents/.gitattributes")
  if echo "$RESPONSE" | grep -q '"message": "Not Found"'; then
    return 1  # No .gitattributes
  fi
  CONTENT=$(echo "$RESPONSE" | sed -n 's/.*"content": "\([^"]*\)".*/\1/p' | base64 -d 2>/dev/null)
  if echo "$CONTENT" | grep -q 'filter=lfs'; then
    return 0  # Uses LFS
  else
    return 1  # Has .gitattributes but no LFS
  fi
}

# Check for git-lfs if needed
if check_lfs; then
  command -v git-lfs >/dev/null 2>&1 || { echo "Error: git-lfs is required for this repository but not installed."; exit 1; }
  echo "Git LFS detected in original repository."
fi

# Set global Git configuration using environment variables
git config --global user.email "$GITHUB_USERNAME@gmail.com"
git config --global user.name "$GITHUB_USERNAME"

# Define the base target mirror repository (without credentials)
MIRROR_BASE="github.com/$GITHUB_USERNAME/$REPO_NAME.git"

# Construct the authenticated mirror URL
MIRROR_REPO="https://$GITHUB_USERNAME:$GITHUB_TOKEN@$MIRROR_BASE"

# Function to check if the target repository exists
check_repo_exists() {
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$API_BASE/repos/$GITHUB_USERNAME/$REPO_NAME")
  if [ "$RESPONSE" -eq 200 ]; then
    return 0  # Exists
  elif [ "$RESPONSE" -eq 404 ]; then
    return 1  # Does not exist
  else
    echo "Error checking repository: HTTP $RESPONSE"
    exit 1
  fi
}

# Function to create the repository
create_repo() {
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
       -d "{\"name\":\"$REPO_NAME\", \"auto_init\":false, \"private\":false}" \
       "$API_BASE/user/repos" > /dev/null
  if [ $? -ne 0 ]; then
    echo "Error creating repository."
    exit 1
  fi
  echo "Repository created successfully."
}

# Check and create repo if necessary
if check_repo_exists; then
  echo "Repository already exists. Proceeding with mirroring (note: this will overwrite existing content)."
else
  echo "Repository does not exist. Creating it now..."
  create_repo
  sleep 2  # Short delay to ensure repo is ready
fi

# Create or use the specified directory for the clone
if [ -n "$LOCAL_PATH" ]; then
  CLONE_DIR="$LOCAL_PATH"
  USE_TEMP_DIR=false
  if [ -d "$CLONE_DIR" ]; then
    echo "Warning: Directory $CLONE_DIR already exists. Contents will be overwritten."
    rm -rf "$CLONE_DIR"
  fi
  mkdir -p "$CLONE_DIR" || { echo "Error creating directory $CLONE_DIR."; exit 1; }
else
  CLONE_DIR=$(mktemp -d -t "${REPO_NAME}.XXXXXX") || { echo "Error creating temporary directory."; exit 1; }
  USE_TEMP_DIR=true
fi

# Create a bare mirrored clone of the original repository
git clone --mirror --progress "$ORIGINAL_REPO" "$CLONE_DIR" || { echo "Error cloning original repository."; rm -rf "$CLONE_DIR"; exit 1; }

# Navigate into the cloned directory
cd "$CLONE_DIR" || { echo "Error navigating to cloned directory."; rm -rf "$CLONE_DIR"; exit 1; }

# Delete non-standard Gerrit refs to avoid push errors (preserves branches and tags)
git for-each-ref --format='%(refname)' refs/users | xargs -r -n1 git update-ref -d
git for-each-ref --format='%(refname)' refs/changes | xargs -r -n1 git update-ref -d

# Delete GitHub-specific PR refs to avoid "deny updating a hidden ref" errors
git for-each-ref --format='%(refname)' refs/pull | xargs -r -n1 git update-ref -d

# Handle Git LFS if present
if grep -q '[lfs]' config; then
  echo "Git LFS detected. Handling LFS objects..."
  git lfs fetch --all || { echo "Error fetching LFS objects."; cd ..; rm -rf "$CLONE_DIR"; exit 1; }
  git lfs push --all "$MIRROR_REPO" || { echo "Error pushing LFS objects."; cd ..; rm -rf "$CLONE_DIR"; exit 1; }
fi

# Push the cleaned mirrored clone to the new GitHub repository
git push --mirror --progress "$MIRROR_REPO" || { echo "Error pushing to mirror repository."; cd ..; rm -rf "$CLONE_DIR"; exit 1; }

# Clean up the local clone (only if using temporary directory)
cd ..
if [ "$USE_TEMP_DIR" = true ]; then
  rm -rf "$CLONE_DIR"
  echo "Temporary directory cleaned up."
else
  echo "Local repository preserved at: $CLONE_DIR"
fi

echo "Mirroring complete. The repository has been duplicated to https://github.com/$GITHUB_USERNAME/$REPO_NAME.git."
