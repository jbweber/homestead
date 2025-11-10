#!/bin/bash
set -euo pipefail

echo "=== Installing clusterctl CLI ==="

# Parse command line arguments
INSTALL_DIR="$HOME/.local/bin"

while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install-dir DIR    Install clusterctl to DIR (default: ~/.local/bin)"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage"
            exit 1
            ;;
    esac
done

# Check if clusterctl is already installed
if command -v clusterctl &> /dev/null; then
    INSTALLED_VERSION=$(clusterctl version | grep "clusterctl version" | awk '{print $3}')
    echo "clusterctl is already installed: $INSTALLED_VERSION"
    echo ""
    echo "To reinstall, remove the existing binary:"
    echo "  sudo rm \$(which clusterctl)"
    exit 0
fi

# Determine latest stable version
echo "Fetching latest clusterctl version..."
CLUSTERCTL_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/cluster-api/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$CLUSTERCTL_VERSION" ]; then
    echo "Error: Could not determine latest clusterctl version"
    exit 1
fi

echo "Latest version: $CLUSTERCTL_VERSION"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download clusterctl binary
DOWNLOAD_URL="https://github.com/kubernetes-sigs/cluster-api/releases/download/${CLUSTERCTL_VERSION}/clusterctl-${OS}-${ARCH}"
echo "Downloading from: $DOWNLOAD_URL"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/clusterctl"
chmod +x "$TEMP_DIR/clusterctl"

# Install to specified directory
mkdir -p "$INSTALL_DIR"
mv "$TEMP_DIR/clusterctl" "$INSTALL_DIR/clusterctl"

echo ""
echo "=== Installation Complete ==="
echo "clusterctl installed to: $INSTALL_DIR/clusterctl"
echo ""

# Verify installation
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "WARNING: $INSTALL_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# Use full path for verification
"$INSTALL_DIR/clusterctl" version

echo ""
echo "Next steps:"
echo "  Run: homestead/capi/02-install-capi-core.sh"
