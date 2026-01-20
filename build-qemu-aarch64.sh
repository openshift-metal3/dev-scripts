#!/bin/bash
# Build qemu-system-aarch64 from source matching the installed QEMU version
# This is needed for ARM VM emulation on x86_64 hosts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/qemu-build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

echo "Building qemu-system-aarch64 from source"

# Get the currently installed QEMU version
if rpm -q qemu-kvm-core &>/dev/null; then
    QEMU_RPM_VERSION=$(rpm -q --queryformat '%{VERSION}' qemu-kvm-core)
    echo "Detected QEMU version from qemu-kvm-core: $QEMU_RPM_VERSION"
elif rpm -q qemu-img &>/dev/null; then
    QEMU_RPM_VERSION=$(rpm -q --queryformat '%{VERSION}' qemu-img)
    echo "Detected QEMU version from qemu-img: $QEMU_RPM_VERSION"
else
    echo "ERROR: Cannot detect QEMU version. Is qemu-kvm installed?"
    exit 1
fi

# Extract major.minor.patch version (strip any release suffix)
QEMU_VERSION="${QEMU_VERSION:-$QEMU_RPM_VERSION}"
echo "Building QEMU version: $QEMU_VERSION"

# Check if already installed
if [ -x "$INSTALL_PREFIX/bin/qemu-system-aarch64" ]; then
    INSTALLED_VERSION=$($INSTALL_PREFIX/bin/qemu-system-aarch64 --version | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    if [ "$INSTALLED_VERSION" = "$QEMU_VERSION" ]; then
        echo "qemu-system-aarch64 version $QEMU_VERSION is already installed at $INSTALL_PREFIX/bin/qemu-system-aarch64"
        echo "Skipping build."
        exit 0
    else
        echo "Found different version installed: $INSTALLED_VERSION, will rebuild"
    fi
fi

# Install build dependencies and AAVMF firmware
echo ""
echo "Installing build dependencies and ARM firmware..."
sudo dnf install -y \
    git \
    gcc \
    gcc-c++ \
    make \
    ninja-build \
    python3 \
    python3-pip \
    glib2-devel \
    pixman-devel \
    zlib-devel \
    libaio-devel \
    libcap-ng-devel \
    libattr-devel \
    libiscsi-devel \
    libnfs-devel \
    libseccomp-devel \
    libselinux-devel \
    libcurl-devel \
    ncurses-devel \
    libudev-devel \
    bzip2 \
    wget \
    edk2-aarch64

# Verify AAVMF firmware files were installed
echo ""
echo "Verifying ARM firmware files..."
AAVMF_CODE="/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw"
AAVMF_VARS="/usr/share/edk2/aarch64/vars-template-pflash.raw"

if [ ! -f "$AAVMF_CODE" ]; then
    echo "ERROR: ARM firmware file not found: $AAVMF_CODE"
    echo "The edk2-aarch64 package may not have installed correctly."
    exit 1
fi

if [ ! -f "$AAVMF_VARS" ]; then
    echo "ERROR: ARM firmware file not found: $AAVMF_VARS"
    echo "The edk2-aarch64 package may not have installed correctly."
    exit 1
fi

echo "  ARM firmware files found:"
echo "    - $AAVMF_CODE"
echo "    - $AAVMF_VARS"

# Install meson if not available or too old
MESON_MIN_VERSION="0.63.0"
if command -v meson &> /dev/null; then
    MESON_VERSION=$(meson --version)
    echo ""
    echo "Found meson version: $MESON_VERSION"
else
    echo ""
    echo "Installing meson via pip..."
    sudo python3 -m pip install meson
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download QEMU source
QEMU_TAR="qemu-${QEMU_VERSION}.tar.xz"
QEMU_URL="https://download.qemu.org/${QEMU_TAR}"
QEMU_DIR="qemu-${QEMU_VERSION}"

if [ ! -f "$QEMU_TAR" ]; then
    echo ""
    echo "Downloading QEMU ${QEMU_VERSION} source from $QEMU_URL..."
    wget "$QEMU_URL"
else
    echo "Using cached tarball: $QEMU_TAR"
fi

# Extract if not already extracted
if [ ! -d "$QEMU_DIR" ]; then
    echo "Extracting $QEMU_TAR..."
    tar -xf "$QEMU_TAR"
else
    echo "Source directory already exists: $QEMU_DIR"
fi

cd "$QEMU_DIR"

# Configure QEMU - only build aarch64 system emulation
# This significantly reduces build time and dependencies
echo ""
echo "Configuring QEMU build..."
echo "  Target: aarch64-softmmu"
echo "  Install prefix: $INSTALL_PREFIX"

./configure \
    --prefix="$INSTALL_PREFIX" \
    --target-list=aarch64-softmmu \
    --enable-system \
    --disable-user \
    --disable-linux-user \
    --disable-bsd-user \
    --disable-docs \
    --disable-guest-agent \
    --disable-werror

# Build
NPROC=$(nproc)
echo ""
echo "Building QEMU (using $NPROC cores)..."
make -j"$NPROC"

# Install
echo ""
echo "Installing qemu-system-aarch64 to $INSTALL_PREFIX/bin..."
sudo make install

# Verify installation
if [ -x "$INSTALL_PREFIX/bin/qemu-system-aarch64" ]; then
    echo ""
    echo "========================================="
    echo "Installation successful!"
    echo "========================================="
    "$INSTALL_PREFIX/bin/qemu-system-aarch64" --version
    echo ""
    echo "Binary location: $INSTALL_PREFIX/bin/qemu-system-aarch64"

    # Check if libvirt can find it
    if virsh capabilities | grep -q aarch64; then
        echo "  libvirt can now emulate aarch64 architecture"
    else
        echo "  Warning: libvirt may need to be restarted to detect aarch64 support"
        echo "  Run: sudo systemctl restart libvirtd"
    fi
else
    echo "ERROR: Installation failed - binary not found at $INSTALL_PREFIX/bin/qemu-system-aarch64"
    exit 1
fi

# Optionally clean up build directory
if [ "${CLEANUP_BUILD:-no}" = "yes" ]; then
    echo ""
    echo "Cleaning up build directory: $BUILD_DIR"
    cd /
    rm -rf "$BUILD_DIR"
fi

echo ""
echo "Done!"
