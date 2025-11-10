#!/bin/bash
# Install Intel oneAPI HPC Toolkit (includes ifx compiler)
# Free for personal use and open source projects

set -e

echo "==================================="
echo "Intel Fortran Compiler Installation"
echo "==================================="
echo ""
echo "Intel Fortran (ifx) is FREE for:"
echo "  • Personal use"
echo "  • Open source projects"
echo "  • Academic use"
echo ""
echo "It has MUCH better ARM64 support than gfortran."
echo ""

# Check if already installed
if command -v ifx &> /dev/null; then
    echo "✓ Intel Fortran (ifx) is already installed!"
    ifx --version
    exit 0
fi

echo "Step 1: Download Intel oneAPI HPC Toolkit"
echo "Please visit:"
echo "  https://www.intel.com/content/www/us/en/developer/tools/oneapi/hpc-toolkit-download.html"
echo ""
echo "Choose:"
echo "  • Platform: macOS"
echo "  • Distribution: Online Installer (recommended)"
echo ""
echo "After downloading, the installer will be named something like:"
echo "  m_HPCKit_p_2024.x.x.xxx_offline.dmg"
echo ""
read -p "Press Enter after you've downloaded the .dmg file..."

# Find the downloaded DMG
DMG_FILE=$(ls -t ~/Downloads/m_HPCKit*.dmg 2>/dev/null | head -1)
if [ -z "$DMG_FILE" ]; then
    echo "❌ Could not find Intel HPC Kit DMG in ~/Downloads"
    echo "Please download manually from the link above."
    exit 1
fi

echo ""
echo "Found: $DMG_FILE"
echo "Step 2: Mounting installer..."
hdiutil attach "$DMG_FILE"

echo ""
echo "Step 3: Running installer..."
echo "In the installer GUI:"
echo "  1. Click 'Continue' through the intro"
echo "  2. Accept the license agreement"
echo "  3. Choose 'Custom Installation'"
echo "  4. UNCHECK everything except 'Intel Fortran Compiler'"
echo "  5. Click 'Install'"
echo ""
echo "This will save ~3GB of space by skipping C++, MPI, etc."
echo ""
read -p "Press Enter after installation completes..."

# Eject the DMG
hdiutil detach /Volumes/m_HPCKit* 2>/dev/null || true

# Set up environment
echo ""
echo "Step 4: Setting up environment..."
if [ -f /opt/intel/oneapi/setvars.sh ]; then
    echo ""
    echo "✓ Intel Fortran installed successfully!"
    echo ""
    echo "To use it, run:"
    echo "  source /opt/intel/oneapi/setvars.sh"
    echo ""
    echo "To make it permanent, add this to your ~/.zshrc:"
    echo "  echo 'source /opt/intel/oneapi/setvars.sh >/dev/null 2>&1' >> ~/.zshrc"
    echo ""

    # Source it now
    source /opt/intel/oneapi/setvars.sh

    echo "Verifying installation..."
    ifx --version

    echo ""
    echo "✓ All set! Now run 'make clean && make' to build fortsh with Intel Fortran."
else
    echo "❌ Installation may have failed. Check /opt/intel/oneapi/"
    exit 1
fi
