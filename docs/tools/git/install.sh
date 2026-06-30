#!/bin/bash
# Install git workflow tools system-wide

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo -e "${CYAN}Installing Git Workflow Tools${NC}"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy scripts
cp "$SCRIPT_DIR/workflow.sh" "$INSTALL_DIR/git-workflow"
cp "$SCRIPT_DIR/cleanup.sh" "$INSTALL_DIR/git-cleanup"

chmod +x "$INSTALL_DIR/git-workflow"
chmod +x "$INSTALL_DIR/git-cleanup"

echo -e "${GREEN}✓ Scripts installed to $INSTALL_DIR${NC}"
echo ""

# Check if in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${CYAN}Add to your shell config:${NC}"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""

    # Detect shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    read -p "Add to $shell_rc? [y/n]: " add_path
    if [[ "$add_path" =~ ^[Yy] ]]; then
        echo "" >> "$shell_rc"
        echo "# Git workflow tools" >> "$shell_rc"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$shell_rc"
        echo -e "${GREEN}✓ Added to $shell_rc${NC}"
        echo "Run: source $shell_rc"
    fi
fi

echo ""
echo "You can now use:"
echo -e "  ${CYAN}git-workflow${NC}  - Sync, squash, and prepare for PR"
echo -e "  ${CYAN}git-cleanup${NC}   - Delete merged branches"
echo ""
