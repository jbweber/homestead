#!/bin/bash
# Install Cilium CLI to ~/.local/bin
# Usage: ./install-cilium-cli.sh

set -euo pipefail

# Ensure ~/.local/bin exists
mkdir -p ~/.local/bin

# Detect architecture
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then
    CLI_ARCH=arm64
fi

# Get latest stable version
echo "Fetching latest Cilium CLI version..."
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
echo "Latest version: ${CILIUM_CLI_VERSION}"

# Download and verify
echo "Downloading Cilium CLI for ${CLI_ARCH}..."
curl -L --fail --remote-name-all \
    https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

echo "Verifying checksum..."
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum

# Extract to ~/.local/bin
echo "Installing to ~/.local/bin..."
tar xzvf cilium-linux-${CLI_ARCH}.tar.gz -C ~/.local/bin

# Cleanup
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

echo ""
echo "Cilium CLI installed successfully!"
echo "Location: ~/.local/bin/cilium"
echo ""
echo "Make sure ~/.local/bin is in your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""

# Verify installation
if ~/.local/bin/cilium version --client 2>/dev/null; then
    echo "Installation verified successfully!"
else
    echo "Warning: Could not verify installation"
fi
