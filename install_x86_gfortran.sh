#!/bin/bash
# Install x86_64 gfortran via Rosetta for stable compilation on macOS ARM64
# This avoids all the gfortran ARM64 bugs

set -e

echo "=============================================="
echo "Installing x86_64 gfortran via Rosetta"
echo "=============================================="
echo ""
echo "Why x86_64 gfortran?"
echo "  • Native ARM64 gfortran has 7+ critical bugs"
echo "  • x86_64 version (via Rosetta) is stable"
echo "  • Only ~5% performance overhead"
echo "  • Much simpler than Intel Fortran"
echo ""

# Check if already installed
if /usr/local/bin/gfortran --version 2>/dev/null | grep -q x86_64; then
    echo "✓ x86_64 gfortran is already installed!"
    /usr/local/bin/gfortran --version
    echo ""
    echo "Now run: make clean && make"
    exit 0
fi

# Check if Rosetta is installed
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "Installing Rosetta 2..."
    softwareupdate --install-rosetta --agree-to-license
fi

echo "Step 1: Installing x86_64 Homebrew (if needed)..."
if [ ! -f /usr/local/bin/brew ]; then
    echo "Installing x86_64 Homebrew..."
    arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "✓ x86_64 Homebrew already installed"
fi

echo ""
echo "Step 2: Installing x86_64 gcc (includes gfortran)..."
arch -x86_64 /usr/local/bin/brew install gcc

echo ""
echo "Step 3: Verifying installation..."
/usr/local/bin/gfortran --version

echo ""
echo "=============================================="
echo "✓ Installation complete!"
echo "=============================================="
echo ""
echo "Compiler locations:"
echo "  ARM64 gfortran (buggy): $(which gfortran)"
echo "  x86_64 gfortran (stable): /usr/local/bin/gfortran"
echo ""
echo "The Makefile will automatically use the stable x86_64 version."
echo ""
echo "Now run:"
echo "  make clean && make"
echo ""
