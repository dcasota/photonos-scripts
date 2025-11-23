#!/bin/bash

set -e

TARGETDIR="$(pwd)/sound"

# Install voice dependencies from sources
rm -rf $TARGETDIR/rpmbuild/
mkdir -p $TARGETDIR/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
echo "%_topdir    $TARGETDIR/rpmbuild" > $TARGETDIR/.rpmmacros

tdnf install -y git sudo wget alsa-lib alsa-utils alsa-lib-devel clang cronie linux-api-headers
tdnf install -y cmake autoconf automake binutils bison diffutils file gawk gcc glibc-devel gzip libtool make patch pkg-config tar

cd $TARGETDIR/rpmbuild/SOURCES
wget https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz
tar -xzf libogg-1.3.5.tar.gz
cd libogg-1.3.5
./configure --prefix=/usr
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
wget https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz
tar -xzf lame-3.100.tar.gz
cd lame-3.100
./configure --prefix=/usr
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
wget https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz
tar -xzf libvorbis-1.3.7.tar.gz
cd libvorbis-1.3.7
./configure --prefix=/usr
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
wget https://downloads.xiph.org/releases/flac/flac-1.4.3.tar.xz
tar -xJf flac-1.4.3.tar.xz
cd flac-1.4.3
./configure --prefix=/usr --enable-static --enable-shared
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
wget https://sourceforge.net/projects/mad/files/libmad/0.15.1b/libmad-0.15.1b.tar.gz
tar -xzf libmad-0.15.1b.tar.gz
cd libmad-0.15.1b
sed -i 's/-fforce-mem//g' configure
./configure --prefix=/usr
make
sudo make install

cd $TARGETDIR/rpmbuild/SOURCES
wget https://sourceforge.net/projects/mpg123/files/mpg123/1.31.3/mpg123-1.31.3.tar.bz2
tar -xjf mpg123-1.31.3.tar.bz2
cd mpg123-1.31.3
./configure --prefix=/usr
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
wget https://sourceforge.net/projects/sox/files/sox/14.4.2/sox-14.4.2.tar.gz
tar -xzf sox-14.4.2.tar.gz
cd sox-14.4.2
./configure --prefix=/usr \
            --with-dyn-lame \
            --with-lame=/usr \
            --with-dyn-mad \
            --with-dyn-sndfile \
            --with-dyn-amrnb \
            --with-dyn-amrwb \
            --with-alsa \
            --with-vorbis \
            --with-flac
make
sudo make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/PortAudio/portaudio
cd portaudio
./configure --prefix=/usr
make
make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/espeak-ng/sonic
cd sonic
make
make install

cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/espeak-ng/pcaudiolib
cd pcaudiolib
./autogen.sh
./configure --prefix=/usr
make
make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/numediart/MBROLA
cd MBROLA
make
sudo cp Bin/mbrola /usr/bin/mbrola


# Base URL for raw files
BASE_URL="https://github.com/numediart/MBROLA-voices/raw/master/data"
# GitHub API URL for the data directory
API_URL="https://api.github.com/repos/numediart/MBROLA-voices/contents/data"

# Output directory for MBROLA voices
OUTPUT_DIR="/usr/share/mbrola"

# Temporary file for voice list
VOICES_FILE=$(mktemp)

# Ensure dependencies are installed
tdnf install -y curl jq wget unzip

# Create output directory with appropriate permissions
sudo mkdir -p "$OUTPUT_DIR"
sudo chmod 755 "$OUTPUT_DIR"

# Fetch voice directories from GitHub API
echo "Fetching list of MBROLA voices..." >&2
if ! curl -s "$API_URL" | jq -r '.[] | select(.type == "dir") | .name' > "$VOICES_FILE"; then
  echo "Error: Failed to fetch voice list from GitHub API. Check your internet connection or API rate limit." >&2
  rm -f "$VOICES_FILE"
  exit 1
fi

# Check if voices were found
if [ ! -s "$VOICES_FILE" ]; then
  echo "Error: No voices found in the repository." >&2
  rm -f "$VOICES_FILE"
  exit 1
fi

# Display the list of voices
echo "Available MBROLA voices:" >&2
cat "$VOICES_FILE" >&2

# Download each voice file
while IFS= read -r voice; do
  echo "Downloading $voice..." >&2
  VOICE_URL="$BASE_URL/$voice/$voice"
  VOICE_DIR="$OUTPUT_DIR/$voice"
  VOICE_FILE="$VOICE_DIR/$voice"

  # Create voice directory
  sudo mkdir -p "$VOICE_DIR"
  sudo chmod 755 "$VOICE_DIR"

  # Download the voice file
  if sudo wget -q "$VOICE_URL" -O "$VOICE_FILE"; then
    sudo chmod 644 "$VOICE_FILE"
    echo "Successfully installed $voice to $VOICE_FILE" >&2
  else
    echo "Warning: Failed to download $voice from $VOICE_URL" >&2
    sudo rm -rf "$VOICE_DIR"
  fi
done < "$VOICES_FILE"

# Clean up
rm -f "$VOICES_FILE"


cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/espeak-ng/espeak-ng
cd espeak-ng
./autogen.sh
./configure --prefix=/usr
make
make install
sudo ldconfig

cd $TARGETDIR/rpmbuild/SOURCES
git clone https://github.com/festvox/flite
cd flite
./configure --prefix=/usr
make
make install
sudo ldconfig

sox -h | grep -E 'mp3|flac'
lame --version
flac --version
arecord -l

echo "Installation complete."
