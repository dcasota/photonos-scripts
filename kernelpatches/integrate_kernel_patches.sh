#!/bin/bash

# crafted by using Grok4 https://grok.com/share/bGVnYWN5_d4f65a52-ce3a-468d-8ec2-3d6bc1fd30ac

# Usage: ./integrate_kernel_patches.sh [kernel_version] [--stop-before-patch VALUE] [--start-from-patch VALUE]
# e.g. 6.12 --stop-before-patch Patch512
# This script installs prerequisites if missing (git, python3, python3-pip), checks/installs Python modules (requests, pytest), 
# clones Photon OS repo, runs spec2git tests, downloads stable patches for the given kernel version, 
# uses spec2git to convert each linux*.spec to Git in a granular way with permutations of defines (with optional stop/start overriding the loop),
# applies each patch as a commit, and converts back. The granular loop applies cumulatively up to each patch for each permutation.
# Integrates checkpoint.conf for resumability: stores kernel_version, spec_file, canister, acvp, last_patch.

# Supported kernel versions
SUPPORTED_KERNELS=("5.10" "6.1" "6.12")

# Parse arguments
KERNEL_VERSION=""
STOP_BEFORE_PATCH=""
START_FROM_PATCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stop-before-patch)
            STOP_BEFORE_PATCH="$2"
            shift 2 ;;
        --start-from-patch)
            START_FROM_PATCH="$2"
            shift 2 ;;
        --help|-h)
            echo "Usage: $0 <kernel_version> [OPTIONS]"
            echo ""
            echo "Supported kernel versions: ${SUPPORTED_KERNELS[*]}"
            echo ""
            echo "Options:"
            echo "  --stop-before-patch VALUE   Stop before specified patch"
            echo "  --start-from-patch VALUE    Start from specified patch"
            echo "  --help, -h                  Show this help"
            exit 0 ;;
        *)
            KERNEL_VERSION="$1"
            shift ;;
    esac
done

# Validate kernel version
if [ -z "$KERNEL_VERSION" ]; then
    echo "ERROR: Kernel version is required."
    echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
    echo "Usage: $0 <kernel_version> [OPTIONS]"
    exit 1
fi

VALID_VERSION=false
for v in "${SUPPORTED_KERNELS[@]}"; do
    if [ "$v" = "$KERNEL_VERSION" ]; then
        VALID_VERSION=true
        break
    fi
done

if [ "$VALID_VERSION" = false ]; then
    echo "ERROR: Unsupported kernel version '$KERNEL_VERSION'"
    echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
    exit 1
fi

# Determine kernel.org base URL based on major version
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_ORG_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/"
echo "Using kernel.org base URL: $KERNEL_ORG_BASE_URL"

PHOTON_DIR="$HOME/photon"
PATCH_DIR="$HOME/kernel_patches_${KERNEL_VERSION}"
SPEC2GIT="$PHOTON_DIR/tools/scripts/spec2git/spec2git.py"
TESTS_DIR="$PHOTON_DIR/tools/scripts/spec2git/tests"
CHECKPOINT_FILE="checkpoint.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_FILE="${SCRIPT_DIR}/patch_routing.skills"

# Determine SPEC_DIR based on kernel version
case "$KERNEL_VERSION" in
    5.10)
        SPEC_DIR="$PHOTON_DIR/SPECS/linux"
        PHOTON_BRANCH="4.0"
        ;;
    6.1)
        SPEC_DIR="$PHOTON_DIR/SPECS/linux/v6.1"
        PHOTON_BRANCH="5.0"
        ;;
    6.12)
        SPEC_DIR="$PHOTON_DIR/SPECS/linux/v6.12"
        PHOTON_BRANCH="common"
        ;;
esac
echo "Spec directory: $SPEC_DIR"
echo "Photon branch: $PHOTON_BRANCH"

# Get available spec files for kernel version
get_available_specs() {
    case "$KERNEL_VERSION" in
        5.10) echo "linux.spec linux-esx.spec linux-rt.spec" ;;
        6.1)  echo "linux.spec linux-esx.spec linux-rt.spec" ;;
        6.12) echo "linux.spec linux-esx.spec" ;;
    esac
}

# Get patch routing from skills file or auto-detect
get_patch_targets() {
    local PATCH_FILE=$1
    local SHA_PREFIX=$2
    
    # Check skills file first
    if [ -f "$SKILLS_FILE" ] && [ -n "$SHA_PREFIX" ]; then
        local ROUTING=$(grep -E "^${SHA_PREFIX}" "$SKILLS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
        if [ -n "$ROUTING" ]; then
            echo "$ROUTING"
            return
        fi
    fi
    
    # Auto-detect based on patch content
    if [ -f "$PATCH_FILE" ]; then
        local HAS_GPU=$(grep -E '^\+\+\+.*drivers/gpu/' "$PATCH_FILE" 2>/dev/null)
        local HAS_KVM=$(grep -E '^\+\+\+.*arch/x86/kvm/' "$PATCH_FILE" 2>/dev/null)
        local HAS_RT=$(grep -E '^\+\+\+.*kernel/sched/.*rt' "$PATCH_FILE" 2>/dev/null)
        local HAS_VIRT=$(grep -E '^\+\+\+.*(hyperv|vmw|xen)/' "$PATCH_FILE" 2>/dev/null)
        
        if [ -n "$HAS_GPU" ]; then
            echo "base"
            return
        fi
        if [ -n "$HAS_KVM" ] || [ -n "$HAS_VIRT" ]; then
            echo "base,esx"
            return
        fi
        if [ -n "$HAS_RT" ]; then
            echo "base,rt"
            return
        fi
    fi
    
    echo "all"
}

# Expand targets to spec file names
expand_targets() {
    local TARGETS=$1
    local AVAILABLE=$2
    local RESULT=""
    
    case "$TARGETS" in
        all)  echo "$AVAILABLE"; return ;;
        none) echo ""; return ;;
    esac
    
    IFS=',' read -ra TARR <<< "$TARGETS"
    for t in "${TARR[@]}"; do
        case "$t" in
            base) echo "$AVAILABLE" | grep -q "linux.spec" && RESULT="$RESULT linux.spec" ;;
            esx)  echo "$AVAILABLE" | grep -q "linux-esx.spec" && RESULT="$RESULT linux-esx.spec" ;;
            rt)   echo "$AVAILABLE" | grep -q "linux-rt.spec" && RESULT="$RESULT linux-rt.spec" ;;
        esac
    done
    echo "$RESULT" | xargs
}

AVAILABLE_SPECS=$(get_available_specs)
echo "Available specs: $AVAILABLE_SPECS"
echo "Skills file: $SKILLS_FILE"

# Network configuration
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-30}"
NETWORK_RETRIES="${NETWORK_RETRIES:-3}"

# Logging setup
LOG_DIR="${LOG_DIR:-/var/log/kernel-backport}"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="$LOG_DIR/integrate_${KERNEL_VERSION}_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Network connectivity check
check_network() {
    local hosts=("github.com" "cdn.kernel.org")
    local attempt=1
    
    log "Checking network connectivity..."
    
    while [ $attempt -le $NETWORK_RETRIES ]; do
        for host in "${hosts[@]}"; do
            if timeout "$NETWORK_TIMEOUT" ping -c 1 "$host" >/dev/null 2>&1; then
                log "Network OK: $host reachable"
                return 0
            fi
            if timeout "$NETWORK_TIMEOUT" curl -s --head --max-time "$NETWORK_TIMEOUT" "https://$host" >/dev/null 2>&1; then
                log "Network OK: $host reachable (curl)"
                return 0
            fi
        done
        
        log "Network check attempt $attempt/$NETWORK_RETRIES failed"
        attempt=$((attempt + 1))
        [ $attempt -le $NETWORK_RETRIES ] && sleep 5
    done
    
    log_error "Network is not available after $NETWORK_RETRIES attempts"
    return 1
}

# Check network before proceeding
if ! check_network; then
    log_error "Aborting due to network unavailability"
    echo "Network is not available. Please check your connection and try again."
    exit 0  # Exit cleanly
fi

log "Starting kernel integration for version $KERNEL_VERSION"
log "Log file: $LOG_FILE"

# install system prerequisites
tdnf install -y git python3 python3-pip rpm-build tar wget util-linux build-essential cmake flex bison xz patch elfutils-libelf-devel elfutils-devel

# Check and install Python modules: requests and pytest
for module in requests pytest; do
    if ! python3 -c "import $module" >/dev/null 2>&1; then
        echo "Python module $module not found. Installing with pip..."
        python3 -m pip install --user "$module"
        if ! python3 -c "import $module" >/dev/null 2>&1; then
            echo "Failed to install $module. Please install manually."
            exit 1
        fi
    else
        echo "Python module $module is already installed."
    fi
done

# Clone Photon OS repository if it doesn't exist
if [ ! -d "$PHOTON_DIR" ]; then
    echo "Cloning Photon OS repository (branch: $PHOTON_BRANCH)..."
    git clone -b "$PHOTON_BRANCH" https://github.com/vmware/photon.git "$PHOTON_DIR"
    echo "Photon OS repository cloned."
else
    echo "Using existing Photon OS repository."
    # Ensure we're on the correct branch
    cd "$PHOTON_DIR"
    CURRENT_BRANCH=$(git branch --show-current)
    if [ "$CURRENT_BRANCH" != "$PHOTON_BRANCH" ]; then
        echo "Switching from $CURRENT_BRANCH to $PHOTON_BRANCH..."
        git fetch origin "$PHOTON_BRANCH"
        git checkout "$PHOTON_BRANCH"
    fi
    cd - > /dev/null
fi

# Run all spec2git tests to verify the tool
cd "$TESTS_DIR" || exit 1
python3 -m pytest .
if [ $? -ne 0 ]; then
    echo "spec2git tests failed. Aborting workflow."
    exit 1
fi
echo "All spec2git tests passed successfully."

# Discover linux*.spec files in the versioned directory, filtered by available specs
cd "$SPEC_DIR" || { echo "Spec directory $SPEC_DIR not found. Aborting."; exit 1; }
SPEC_FILES=()
for spec in $AVAILABLE_SPECS; do
    if [ -f "$spec" ]; then
        SPEC_FILES+=("$spec")
    else
        echo "WARNING: Expected spec file $spec not found in $SPEC_DIR"
    fi
done
if [ ${#SPEC_FILES[@]} -eq 0 ]; then
    echo "No linux*.spec files found in $SPEC_DIR. Aborting."
    exit 1
fi
echo "Detected spec files: ${SPEC_FILES[*]}"
echo "Using skills-based patch routing from: $SKILLS_FILE"

# Function to update checkpoint file
update_checkpoint() {
    local kernel=$1
    local spec=$2
    local canister=$3
    local acvp=$4
    local last_patch=$5
    echo "kernel_version=$kernel" > "$CHECKPOINT_FILE"
    echo "spec_file=$spec" >> "$CHECKPOINT_FILE"
    echo "canister=$canister" >> "$CHECKPOINT_FILE"
    echo "acvp=$acvp" >> "$CHECKPOINT_FILE"
    echo "last_patch=$last_patch" >> "$CHECKPOINT_FILE"
    echo "Checkpoint updated: kernel $kernel, spec $spec, canister $canister, acvp $acvp, last_patch $last_patch"
}

# Function for safe Git directory removal
safe_remove_git_dir() {
    local dir=$1
    if [ -d "$dir" ]; then
        find "$dir" -name '*.lock' -delete
        rm -rf "$dir"
        sleep 1  # Brief pause to avoid race conditions
    fi
}

# Initialize starting points (defaults)
START_SPEC_INDEX=0
START_CANISTER=0
START_ACVP=0
START_N=1

# If checkpoint file exists, read and validate
if [ -f "$CHECKPOINT_FILE" ]; then
    KERNEL_FROM_FILE=$(grep '^kernel_version=' "$CHECKPOINT_FILE" | cut -d= -f2)
    SPEC_FROM_FILE=$(grep '^spec_file=' "$CHECKPOINT_FILE" | cut -d= -f2)
    CANISTER_FROM_FILE=$(grep '^canister=' "$CHECKPOINT_FILE" | cut -d= -f2)
    ACVP_FROM_FILE=$(grep '^acvp=' "$CHECKPOINT_FILE" | cut -d= -f2)
    LAST_PATCH_FROM_FILE=$(grep '^last_patch=' "$CHECKPOINT_FILE" | cut -d= -f2)

    # Find if SPEC_FROM_FILE is in SPEC_FILES and get index
    SPEC_FOUND=0
    for i in "${!SPEC_FILES[@]}"; do
        if [ "${SPEC_FILES[$i]}" = "$SPEC_FROM_FILE" ]; then
            START_SPEC_INDEX=$i
            SPEC_FOUND=1
            break
        fi
    done

    # If spec found, load its total patches for validation
    if [ $SPEC_FOUND -eq 1 ]; then
        TOTAL_PATCHES_FOR_RESUME=$(grep -c '^Patch[0-9]*:' "$SPEC_DIR/$SPEC_FROM_FILE")
        # Validate content
        if [[ -n "$KERNEL_FROM_FILE" && "$CANISTER_FROM_FILE" =~ ^[01]$ && "$ACVP_FROM_FILE" =~ ^[01]$ && "$LAST_PATCH_FROM_FILE" =~ ^[0-9]+$ && $LAST_PATCH_FROM_FILE -le $TOTAL_PATCHES_FOR_RESUME ]]; then
            # Verify checkpoint kernel matches requested kernel
            if [ "$KERNEL_FROM_FILE" != "$KERNEL_VERSION" ]; then
                echo "WARNING: Checkpoint kernel ($KERNEL_FROM_FILE) differs from requested ($KERNEL_VERSION). Starting fresh."
                rm -f "$CHECKPOINT_FILE"
            else
                START_CANISTER=$CANISTER_FROM_FILE
                START_ACVP=$ACVP_FROM_FILE
                if [ "$LAST_PATCH_FROM_FILE" -ge "$TOTAL_PATCHES_FOR_RESUME" ]; then
                    # Spec completed, advance to next spec
                    START_SPEC_INDEX=$((START_SPEC_INDEX + 1))
                    START_CANISTER=0
                    START_ACVP=0
                    START_N=1
                    echo "Previous spec $SPEC_FROM_FILE completed. Advancing to spec index $START_SPEC_INDEX."
                else
                    START_N=$((LAST_PATCH_FROM_FILE + 1))
                fi
                echo "Resuming from checkpoint: spec $SPEC_FROM_FILE (index $START_SPEC_INDEX), canister $START_CANISTER, acvp $START_ACVP, starting from patch $START_N"
            fi
        else
            echo "Invalid checkpoint file content. Proceeding without."
        fi
    else
        echo "Checkpoint spec_file not found in current list. Proceeding without."
    fi
else
    echo "No checkpoint file found. Starting fresh."
fi

# Create patch directory
mkdir -p "$PATCH_DIR"

# Embedded Python script to download and decompress all stable patches for the given version
# It loops until downloads fail (404), making it versatile for any kernel version
python3 - <<EOF
import requests
import lzma
import os

kernel_version = "$KERNEL_VERSION"
base_url = "$KERNEL_ORG_BASE_URL"
patch_num = 1
output_dir = '$PATCH_DIR'

print(f"Downloading stable patches for kernel {kernel_version} from {base_url}")

while True:
    patch_file = f'patch-{kernel_version}.{patch_num}.xz'
    url = base_url + patch_file
    response = requests.get(url)
    if response.status_code != 200:
        print(f"No more patches found after {patch_num - 1}.")
        break

    xz_path = os.path.join(output_dir, patch_file)
    with open(xz_path, 'wb') as f:
        f.write(response.content)

    patch_path = os.path.join(output_dir, f'patch-{kernel_version}.{patch_num}')
    with lzma.open(xz_path) as f_in, open(patch_path, 'wb') as f_out:
        f_out.write(f_in.read())

    print(f'Downloaded and decompressed {patch_file}')
    patch_num += 1
EOF

# Loop over spec files, permutations, and granular patches with resumability
cd "$SPEC_DIR" || exit 1
for ((spec_index=START_SPEC_INDEX; spec_index<${#SPEC_FILES[@]}; spec_index++)); do
    CURRENT_SPEC="${SPEC_FILES[$spec_index]}"
    echo "Processing spec file: $CURRENT_SPEC"

    # Count the number of patches for this spec file
    TOTAL_PATCHES=$(grep -c '^Patch[0-9]*:' "$CURRENT_SPEC")
    echo "Detected $TOTAL_PATCHES patches in $CURRENT_SPEC."

    # Reset inner starts if not resuming the same spec
    if [ $spec_index -gt $START_SPEC_INDEX ]; then
        START_CANISTER=0
        START_ACVP=0
        START_N=1
    fi

    for canister in $(seq $START_CANISTER 1); do
        if [ $canister -eq $START_CANISTER ]; then
            acvp_start=$START_ACVP
        else
            acvp_start=0
        fi
        for acvp in $(seq $acvp_start 1); do
            SPEC_BASE="${CURRENT_SPEC%.*}"  # e.g., linux-esx
            GIT_DIR="$HOME/linux-git-${SPEC_BASE}-c${canister}-a${acvp}-${KERNEL_VERSION}"
            UPDATED_SPEC="${CURRENT_SPEC}-c${canister}-a${acvp}"
            echo "Processing permutation: canister_build=$canister, acvp_build=$acvp for $CURRENT_SPEC"

            if [ $canister -eq $START_CANISTER ] && [ $acvp -eq $START_ACVP ]; then
                n_start=$START_N
            else
                n_start=1
            fi

            # Inner loop for granular processing of each patch (cumulative up to n)
            for n in $(seq $n_start $TOTAL_PATCHES); do
                STOP_N=$((n + 1))
                safe_remove_git_dir "$GIT_DIR"
                SPEC2GIT_CMD="python3 \"$SPEC2GIT\" \"$CURRENT_SPEC\" --output-dir \"$GIT_DIR\" --define canister_build=$canister --define acvp_build=$acvp --stop-before-patch $STOP_N --force"
                if [ -n "$START_FROM_PATCH" ]; then
                    SPEC2GIT_CMD="$SPEC2GIT_CMD --start-from-patch \"$START_FROM_PATCH\""
                fi
                eval $SPEC2GIT_CMD
                if [ $? -ne 0 ]; then
                    echo "spec2git conversion failed for patch $n. Aborting loop."
                    exit 1
                fi
                echo "Granular conversion up to patch $n for this permutation completed."

                # Update checkpoint after successful step
                update_checkpoint "$KERNEL_VERSION" "$CURRENT_SPEC" "$canister" "$acvp" "$n"
            done

            # After granular loop, the GIT_DIR has the full conversion (from last iteration)
            echo "Full conversion completed for permutation: canister_build=$canister, acvp_build=$acvp at $GIT_DIR for $CURRENT_SPEC."

            # Disable auto gc in the Git repo
            cd "$GIT_DIR" || exit 1
            git config gc.auto 0

            # Apply each decompressed stable patch in the Git repo
            for patch_file in $(ls "$PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | sort -V); do
                if [ -f "$patch_file" ]; then
                    git apply "$patch_file"
                    if [ $? -eq 0 ]; then
                        git add -A
                        git commit -m "Applied stable patch: $(basename "$patch_file")" || echo "No changes to commit for this patch."
                        echo "Successfully applied and committed $patch_file for this permutation."
                    else
                        echo "Warning: $patch_file did not apply cleanly for this permutation. Manual resolution may be needed."
                    fi
                fi
            done

            # Convert back to spec using git2spec, adding a changelog entry
            cd "$SPEC_DIR" || exit 1
            python3 "$SPEC2GIT" "$CURRENT_SPEC" --git2spec --git-repo "$GIT_DIR" --changelog "Integrated stable patches for Linux kernel $KERNEL_VERSION with canister_build=$canister acvp_build=$acvp"
            if [ $? -ne 0 ]; then
                echo "git2spec failed for this permutation. Aborting."
                exit 1
            fi
            echo "Converted back to updated spec file for this permutation: $SPEC_DIR/$UPDATED_SPEC"

            # Validate the updated spec with rpmspec
            rpmspec --parse "$UPDATED_SPEC" > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "Updated spec $UPDATED_SPEC is invalid (rpmspec parse failed). Aborting."
                exit 1
            fi
            echo "Updated spec $UPDATED_SPEC validated successfully."

            # Run targeted pytest after git2spec for this constellation
            cd "$TESTS_DIR" || exit 1
            python3 -m pytest test_git2spec.py test_end_to_end.py
            if [ $? -ne 0 ]; then
                echo "Targeted pytest failed for this constellation. Aborting."
                exit 1
            fi
            echo "Targeted pytest passed for this constellation."

            # Rename the updated spec to avoid overwriting
            mv "$CURRENT_SPEC" "$UPDATED_SPEC"
        done
    done
done

# After completion, remove checkpoint to avoid unintended resumes (or comment out)
rm -f "$CHECKPOINT_FILE"

# Optional cleanup (comment out if you want to keep files for inspection, especially for resuming)
# rm -rf $HOME/linux-git-* "$PATCH_DIR"

echo "Workflow complete. Updated spec files generated for each permutation and spec file."
