# configuresound.sh User Manual

## Overview

`configuresound.sh` is a comprehensive audio stack installation script for Photon OS. It builds and installs audio libraries, codecs, and text-to-speech (TTS) engines from source, enabling full audio playback, recording, and speech synthesis capabilities.

---

## Usage

```bash
sudo ./configuresound.sh
```

The script runs non-interactively and installs all components automatically.

---

## Prerequisites

- Photon OS with `tdnf` package manager
- Root/sudo privileges
- Internet connection (for downloading sources)
- Sufficient disk space (~500MB for sources and builds)

---

## What It Installs

### System Packages (via tdnf)

The script first installs required system packages:

| Package | Purpose |
|---------|---------|
| `alsa-lib`, `alsa-utils`, `alsa-lib-devel` | ALSA sound system |
| `git`, `wget`, `curl` | Download tools |
| `cmake`, `autoconf`, `automake` | Build tools |
| `gcc`, `clang`, `make` | Compilers |
| `pkg-config`, `libtool` | Build utilities |
| `jq` | JSON parsing (for MBROLA voice list) |

### Audio Libraries (built from source)

| Library | Version | Description |
|---------|---------|-------------|
| **libogg** | 1.3.5 | Ogg container format library |
| **libvorbis** | 1.3.7 | Vorbis audio codec |
| **FLAC** | 1.4.3 | Free Lossless Audio Codec |
| **LAME** | 3.100 | MP3 encoder |
| **libmad** | 0.15.1b | MPEG audio decoder |
| **mpg123** | 1.31.3 | Fast MP3 player/decoder |
| **SoX** | 14.4.2 | Sound eXchange - audio processing tool |
| **PortAudio** | latest | Cross-platform audio I/O |

### Text-to-Speech Engines (built from source)

| Engine | Description |
|--------|-------------|
| **Sonic** | Speed/pitch audio processor |
| **pcaudiolib** | Portable C audio library |
| **MBROLA** | Diphone-based speech synthesizer |
| **MBROLA Voices** | All available language voices |
| **eSpeak NG** | Compact open-source TTS |
| **Flite** | Fast, lightweight TTS engine |

---

## Installation Directory

All source downloads and builds occur in:

```
$(pwd)/sound/rpmbuild/
    BUILD/
    RPMS/
    SOURCES/    <- Source archives and git clones
    SPECS/
    SRPMS/
```

Libraries are installed to `/usr` prefix (e.g., `/usr/lib`, `/usr/bin`).

MBROLA voices are installed to `/usr/share/mbrola/`.

---

## Build Process

For each library, the script follows this pattern:

1. **Download** - wget/git clone the source
2. **Extract** - Unpack archive (tar, xz, bz2)
3. **Configure** - Run `./configure --prefix=/usr`
4. **Build** - Run `make`
5. **Install** - Run `sudo make install`
6. **Update cache** - Run `sudo ldconfig`

### SoX Configuration

SoX is built with dynamic loading support for multiple formats:

```bash
./configure --prefix=/usr \
    --with-dyn-lame \      # MP3 encoding
    --with-lame=/usr \
    --with-dyn-mad \       # MP3 decoding
    --with-dyn-sndfile \
    --with-dyn-amrnb \
    --with-dyn-amrwb \
    --with-alsa \          # ALSA support
    --with-vorbis \        # Ogg Vorbis
    --with-flac            # FLAC
```

---

## MBROLA Voices

The script automatically downloads all available MBROLA voices from the official repository:

- Fetches voice list from GitHub API
- Downloads each voice to `/usr/share/mbrola/<voice>/<voice>`
- Supports 30+ languages including: en, de, fr, es, it, pt, nl, pl, ru, etc.

### Voice Directory Structure

```
/usr/share/mbrola/
    en1/
        en1         <- Voice data file
    de1/
        de1
    fr1/
        fr1
    ...
```

---

## Verification

After installation, the script runs verification commands:

```bash
# Check SoX format support
sox -h | grep -E 'mp3|flac'

# Check LAME version
lame --version

# Check FLAC version
flac --version

# List audio recording devices
arecord -l
```

---

## Post-Installation Usage

### Audio Playback

```bash
# Play audio file with SoX
play audio.mp3
play audio.flac
play audio.ogg

# Convert audio formats
sox input.wav output.mp3
sox input.flac output.ogg
```

### Text-to-Speech

```bash
# eSpeak NG
espeak-ng "Hello, this is a test"
espeak-ng -v en "Hello" -w output.wav

# eSpeak with MBROLA voice
espeak-ng -v mb-en1 "Hello with MBROLA"

# Flite
flite -t "Hello from Flite" -o output.wav
```

### Audio Recording

```bash
# Record from microphone (ALSA)
arecord -f cd -t wav -d 10 recording.wav

# List recording devices
arecord -l
```

---

## Troubleshooting

### No Sound Devices Found

```bash
# Check ALSA devices
aplay -l
cat /proc/asound/cards

# Load sound modules (if VM)
modprobe snd-hda-intel
```

### Library Not Found Errors

```bash
# Update library cache
sudo ldconfig

# Check library paths
echo $LD_LIBRARY_PATH
ldconfig -p | grep <library>
```

### MBROLA Voice Download Fails

The script uses GitHub API which has rate limits. If downloads fail:

```bash
# Check rate limit
curl -s https://api.github.com/rate_limit | jq '.rate'

# Manual download
wget https://github.com/numediart/MBROLA-voices/raw/master/data/<voice>/<voice>
```

### Build Failures

Check for missing dependencies:

```bash
# Install additional dev packages if needed
tdnf install -y glibc-devel linux-api-headers
```

---

## Cleanup

To remove build artifacts after installation:

```bash
rm -rf $(pwd)/sound/rpmbuild/
```

**Note:** This only removes source files, not installed libraries.

---

## Installed Commands

After running the script, these commands are available:

| Command | Description |
|---------|-------------|
| `sox`, `play`, `rec` | SoX audio tools |
| `lame` | MP3 encoder |
| `flac` | FLAC encoder/decoder |
| `mpg123` | MP3 player |
| `espeak-ng` | Text-to-speech |
| `flite` | Lightweight TTS |
| `mbrola` | MBROLA synthesizer |
| `aplay`, `arecord` | ALSA playback/recording |

---

## Version Information

| Component | Version |
|-----------|---------|
| libogg | 1.3.5 |
| libvorbis | 1.3.7 |
| FLAC | 1.4.3 |
| LAME | 3.100 |
| libmad | 0.15.1b |
| mpg123 | 1.31.3 |
| SoX | 14.4.2 |
| PortAudio | latest (git) |
| Sonic | latest (git) |
| eSpeak NG | latest (git) |
| Flite | latest (git) |
| MBROLA | latest (git) |
