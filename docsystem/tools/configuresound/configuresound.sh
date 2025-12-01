#!/bin/bash
#
# configuresound.sh - Audio stack installation script for Photon OS
#
# Installs audio libraries, codecs, and text-to-speech engines from source.
# See configuresound-manual.md for detailed documentation.
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME="$(basename "$0")"
TARGETDIR="${SOUND_TARGET_DIR:-$(pwd)/sound}"
SOURCES_DIR="$TARGETDIR/rpmbuild/SOURCES"
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/configuresound-$(date +%Y%m%d-%H%M%S).log"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"

# MBROLA configuration
MBROLA_API_URL="https://api.github.com/repos/numediart/MBROLA-voices/contents/data"
MBROLA_BASE_URL="https://github.com/numediart/MBROLA-voices/raw/master/data"
MBROLA_OUTPUT_DIR="/usr/share/mbrola"

# Component versions
LIBOGG_VERSION="1.3.5"
LIBVORBIS_VERSION="1.3.7"
FLAC_VERSION="1.4.3"
LAME_VERSION="3.100"
LIBMAD_VERSION="0.15.1b"
MPG123_VERSION="1.31.3"
SOX_VERSION="14.4.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

die() {
    log_error "$*"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root or with sudo"
    fi
}

check_command() {
    command -v "$1" &>/dev/null
}

check_internet() {
    log_info "Checking internet connectivity..."
    if ! curl -s --connect-timeout 5 https://github.com &>/dev/null; then
        die "No internet connection. Please check your network."
    fi
    log_success "Internet connectivity OK"
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed with exit code $exit_code"
        log_error "Check log file for details: $LOG_FILE"
    fi
}

trap cleanup_on_error EXIT

# =============================================================================
# Download Functions with Retry
# =============================================================================

download_file() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-3}"
    local retry_delay="${4:-5}"
    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        log_info "Downloading $url (attempt $attempt/$max_retries)..."
        if wget --timeout=30 --tries=1 -q "$url" -O "$output"; then
            log_success "Downloaded $(basename "$output")"
            return 0
        fi
        log_warn "Download failed, retrying in ${retry_delay}s..."
        sleep "$retry_delay"
        ((attempt++))
    done

    log_error "Failed to download $url after $max_retries attempts"
    return 1
}

git_clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local max_retries="${3:-3}"
    local attempt=1

    if [[ -d "$target_dir/.git" ]]; then
        log_info "Updating existing repo: $(basename "$target_dir")"
        (
            cd "$target_dir"
            git fetch --all --quiet || true
            git reset --hard origin/HEAD --quiet || git reset --hard HEAD --quiet
        )
        return 0
    fi

    while [[ $attempt -le $max_retries ]]; do
        log_info "Cloning $repo_url (attempt $attempt/$max_retries)..."
        if git clone --depth 1 --quiet "$repo_url" "$target_dir" 2>/dev/null; then
            log_success "Cloned $(basename "$repo_url")"
            return 0
        fi
        log_warn "Clone failed, retrying..."
        rm -rf "$target_dir"
        sleep 3
        ((attempt++))
    done

    log_error "Failed to clone $repo_url after $max_retries attempts"
    return 1
}

# =============================================================================
# Build Functions
# =============================================================================

build_autotools_project() {
    local name="$1"
    local configure_opts="${2:-}"
    
    log_info "Building $name..."
    
    if [[ -f autogen.sh ]]; then
        ./autogen.sh >> "$LOG_FILE" 2>&1 || die "autogen.sh failed for $name"
    fi
    
    # shellcheck disable=SC2086
    ./configure --prefix=/usr $configure_opts >> "$LOG_FILE" 2>&1 || die "configure failed for $name"
    make -j"$PARALLEL_JOBS" >> "$LOG_FILE" 2>&1 || die "make failed for $name"
    make install >> "$LOG_FILE" 2>&1 || die "make install failed for $name"
    ldconfig
    
    log_success "Installed $name"
}

build_make_project() {
    local name="$1"
    
    log_info "Building $name..."
    make -j"$PARALLEL_JOBS" >> "$LOG_FILE" 2>&1 || die "make failed for $name"
    make install >> "$LOG_FILE" 2>&1 || die "make install failed for $name"
    ldconfig 2>/dev/null || true
    
    log_success "Installed $name"
}

# =============================================================================
# Installation Functions
# =============================================================================

install_system_packages() {
    log_info "Installing system packages..."
    
    local packages=(
        git sudo wget curl
        alsa-lib alsa-utils alsa-lib-devel
        clang cronie linux-api-headers
        cmake autoconf automake binutils bison
        diffutils file gawk gcc glibc-devel gzip
        libtool make patch pkg-config tar
        jq unzip
    )
    
    tdnf install -y "${packages[@]}" >> "$LOG_FILE" 2>&1 || die "Failed to install system packages"
    log_success "System packages installed"
}

install_libogg() {
    local archive="libogg-${LIBOGG_VERSION}.tar.gz"
    local dir="libogg-${LIBOGG_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://downloads.xiph.org/releases/ogg/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xzf "$archive"
    cd "$dir"
    build_autotools_project "libogg"
}

install_lame() {
    local archive="lame-${LAME_VERSION}.tar.gz"
    local dir="lame-${LAME_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://sourceforge.net/projects/lame/files/lame/${LAME_VERSION}/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xzf "$archive"
    cd "$dir"
    build_autotools_project "lame"
}

install_libvorbis() {
    local archive="libvorbis-${LIBVORBIS_VERSION}.tar.gz"
    local dir="libvorbis-${LIBVORBIS_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://downloads.xiph.org/releases/vorbis/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xzf "$archive"
    cd "$dir"
    build_autotools_project "libvorbis"
}

install_flac() {
    local archive="flac-${FLAC_VERSION}.tar.xz"
    local dir="flac-${FLAC_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://downloads.xiph.org/releases/flac/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xJf "$archive"
    cd "$dir"
    build_autotools_project "flac" "--enable-static --enable-shared"
}

install_libmad() {
    local archive="libmad-${LIBMAD_VERSION}.tar.gz"
    local dir="libmad-${LIBMAD_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://sourceforge.net/projects/mad/files/libmad/${LIBMAD_VERSION}/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xzf "$archive"
    cd "$dir"
    
    # Fix deprecated compiler flag
    sed -i 's/-fforce-mem//g' configure
    
    build_autotools_project "libmad"
}

install_mpg123() {
    local archive="mpg123-${MPG123_VERSION}.tar.bz2"
    local dir="mpg123-${MPG123_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://sourceforge.net/projects/mpg123/files/mpg123/${MPG123_VERSION}/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xjf "$archive"
    cd "$dir"
    build_autotools_project "mpg123"
}

install_sox() {
    local archive="sox-${SOX_VERSION}.tar.gz"
    local dir="sox-${SOX_VERSION}"
    
    cd "$SOURCES_DIR"
    
    if [[ ! -f "$archive" ]]; then
        download_file "https://sourceforge.net/projects/sox/files/sox/${SOX_VERSION}/$archive" "$archive"
    fi
    
    rm -rf "$dir"
    tar -xzf "$archive"
    cd "$dir"
    
    local sox_opts="--with-dyn-lame --with-lame=/usr --with-dyn-mad"
    sox_opts+=" --with-dyn-sndfile --with-dyn-amrnb --with-dyn-amrwb"
    sox_opts+=" --with-alsa --with-vorbis --with-flac"
    
    build_autotools_project "sox" "$sox_opts"
}

install_portaudio() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/PortAudio/portaudio" "portaudio"
    cd portaudio
    build_autotools_project "portaudio"
}

install_sonic() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/espeak-ng/sonic" "sonic"
    cd sonic
    build_make_project "sonic"
}

install_pcaudiolib() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/espeak-ng/pcaudiolib" "pcaudiolib"
    cd pcaudiolib
    build_autotools_project "pcaudiolib"
}

install_mbrola() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/numediart/MBROLA" "MBROLA"
    cd MBROLA
    
    log_info "Building MBROLA..."
    make -j"$PARALLEL_JOBS" >> "$LOG_FILE" 2>&1 || die "make failed for MBROLA"
    
    cp Bin/mbrola /usr/bin/mbrola
    chmod 755 /usr/bin/mbrola
    
    log_success "Installed MBROLA"
}

install_mbrola_voices() {
    log_info "Installing MBROLA voices..."
    
    local voices_file
    voices_file=$(mktemp)
    
    mkdir -p "$MBROLA_OUTPUT_DIR"
    chmod 755 "$MBROLA_OUTPUT_DIR"
    
    # Fetch voice list with retry
    local attempt=1
    local max_retries=3
    
    while [[ $attempt -le $max_retries ]]; do
        log_info "Fetching MBROLA voice list (attempt $attempt/$max_retries)..."
        if curl -s --connect-timeout 10 "$MBROLA_API_URL" | jq -r '.[] | select(.type == "dir") | .name' > "$voices_file" 2>/dev/null; then
            if [[ -s "$voices_file" ]]; then
                break
            fi
        fi
        log_warn "Failed to fetch voice list, retrying..."
        sleep 3
        ((attempt++))
    done
    
    if [[ ! -s "$voices_file" ]]; then
        log_warn "Could not fetch MBROLA voice list. Skipping voice installation."
        log_warn "You can manually install voices later from: $MBROLA_BASE_URL"
        rm -f "$voices_file"
        return 0
    fi
    
    local voice_count
    voice_count=$(wc -l < "$voices_file")
    log_info "Found $voice_count MBROLA voices"
    
    local installed=0
    local failed=0
    
    while IFS= read -r voice; do
        local voice_url="$MBROLA_BASE_URL/$voice/$voice"
        local voice_dir="$MBROLA_OUTPUT_DIR/$voice"
        local voice_file="$voice_dir/$voice"
        
        mkdir -p "$voice_dir"
        chmod 755 "$voice_dir"
        
        if wget --timeout=30 --tries=2 -q "$voice_url" -O "$voice_file" 2>/dev/null; then
            chmod 644 "$voice_file"
            installed=$((installed + 1))
        else
            rm -rf "$voice_dir"
            failed=$((failed + 1))
        fi
    done < "$voices_file"
    
    rm -f "$voices_file"
    
    log_success "Installed $installed MBROLA voices ($failed failed)"
}

install_espeak_ng() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/espeak-ng/espeak-ng" "espeak-ng"
    cd espeak-ng
    build_autotools_project "espeak-ng"
}

install_flite() {
    cd "$SOURCES_DIR"
    git_clone_or_update "https://github.com/festvox/flite" "flite"
    cd flite
    build_autotools_project "flite"
}

# =============================================================================
# Verification Functions
# =============================================================================

verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check commands
    local commands=("sox" "lame" "flac" "mpg123" "espeak-ng" "flite" "mbrola" "arecord")
    for cmd in "${commands[@]}"; do
        if check_command "$cmd"; then
            log_success "$cmd is available"
        else
            log_warn "$cmd is NOT available"
            ((errors++))
        fi
    done
    
    # Check SoX format support
    if sox -h 2>/dev/null | grep -qE 'mp3|flac'; then
        log_success "SoX has MP3/FLAC support"
    else
        log_warn "SoX may be missing MP3/FLAC support"
    fi
    
    # Check library loading
    if ldconfig -p | grep -q libogg; then
        log_success "Audio libraries are properly linked"
    else
        log_warn "Some audio libraries may not be properly linked"
    fi
    
    # Display versions
    echo ""
    log_info "Installed versions:"
    lame --version 2>/dev/null | head -1 || true
    flac --version 2>/dev/null || true
    sox --version 2>/dev/null | head -1 || true
    espeak-ng --version 2>/dev/null || true
    
    # List audio devices
    echo ""
    log_info "Available audio devices:"
    arecord -l 2>/dev/null || log_warn "No recording devices found (may be normal in VM)"
    
    return $errors
}

# =============================================================================
# Main
# =============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Audio stack installation script for Photon OS.

Options:
    -h, --help          Show this help message
    -v, --verify-only   Only verify existing installation
    -c, --clean         Clean build directory before starting
    -j, --jobs N        Number of parallel build jobs (default: $(nproc))

Environment Variables:
    SOUND_TARGET_DIR    Target directory for sources (default: \$(pwd)/sound)
    PARALLEL_JOBS       Number of parallel build jobs

Examples:
    $SCRIPT_NAME                    # Full installation
    $SCRIPT_NAME --verify-only      # Check existing installation
    $SCRIPT_NAME --clean -j 4       # Clean install with 4 parallel jobs

EOF
}

main() {
    local verify_only=false
    local clean_first=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verify-only)
                verify_only=true
                shift
                ;;
            -c|--clean)
                clean_first=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Header
    echo "=============================================="
    echo "  Photon OS Audio Stack Installer"
    echo "=============================================="
    echo ""
    
    if $verify_only; then
        verify_installation
        exit $?
    fi
    
    # Pre-flight checks
    check_root
    check_internet
    
    # Setup directories
    if $clean_first; then
        log_info "Cleaning build directory..."
        rm -rf "$TARGETDIR/rpmbuild"
    fi
    
    mkdir -p "$TARGETDIR"
    mkdir -p "$SOURCES_DIR"
    echo "%_topdir    $TARGETDIR/rpmbuild" > "$TARGETDIR/.rpmmacros"
    
    # Create log file early
    touch "$LOG_FILE" || die "Cannot create log file: $LOG_FILE"
    
    log_info "Build log: $LOG_FILE"
    log_info "Using $PARALLEL_JOBS parallel build jobs"
    echo ""
    
    # Install components
    install_system_packages
    
    log_info "Installing audio libraries..."
    install_libogg
    install_lame
    install_libvorbis
    install_flac
    install_libmad
    install_mpg123
    install_sox
    install_portaudio
    
    log_info "Installing TTS components..."
    install_sonic
    install_pcaudiolib
    install_mbrola
    install_mbrola_voices
    install_espeak_ng
    install_flite
    
    echo ""
    echo "=============================================="
    verify_installation
    echo "=============================================="
    echo ""
    log_success "Installation complete!"
    log_info "Log file: $LOG_FILE"
}

main "$@"
