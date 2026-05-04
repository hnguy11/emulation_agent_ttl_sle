#!/bin/bash
#===============================================================================
# init_agent.sh — NVL-AX Emulation Agent Initializer
#
# This script sets up the sle_emulation_agent for GitHub Copilot CLI:
#   1. Asks for your working disk directory
#   2. Moves ~/.copilot/agents to the working disk (avoids NFS home quota)
#   3. Creates a symlink back to ~/.copilot/agents
#   4. Locates the emulation_agent KB and copies the agent file
#   5. Hardcodes KB_ROOT in the agent so it's ready to use
#
# Usage:  bash init_agent.sh
#===============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERROR]${RESET} $*"; }
die()   { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_FILE="sle_emulation_agent.agent.md"
COPILOT_HOME="$HOME/.copilot"
AGENTS_SRC="$COPILOT_HOME/agents"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   NVL-AX Emulation Agent — Init Script              ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 1: Ask for working disk directory
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 1: Working disk directory${RESET}"
echo "  This is your large project disk (NOT the model workarea)."
echo "  Example: /nfs/site/disks/ive_sle_zsc11_<userid>"
echo ""
read -rp "  Enter your working disk path: " WORKING_DISK

# Validate
WORKING_DISK="${WORKING_DISK%/}"  # strip trailing slash
[ -z "$WORKING_DISK" ] && die "No path provided."
[ ! -d "$WORKING_DISK" ] && die "Directory does not exist: $WORKING_DISK"

ok "Working disk: $WORKING_DISK"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 2: Copy ~/.copilot/agents to working disk
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 2: Copy agents to working disk${RESET}"

DEST_AGENTS="$WORKING_DISK/homedir/.copilot/agents"

# Create destination directory tree
mkdir -p "$DEST_AGENTS"
ok "Created directory: $DEST_AGENTS"

# Copy existing agents if the source exists and is a real directory (not a symlink)
if [ -d "$AGENTS_SRC" ] && [ ! -L "$AGENTS_SRC" ]; then
    cp -a "$AGENTS_SRC"/. "$DEST_AGENTS"/
    ok "Copied existing agents from $AGENTS_SRC → $DEST_AGENTS"
elif [ -L "$AGENTS_SRC" ]; then
    # If it's already a symlink, copy from the symlink target
    LINK_TARGET="$(readlink -f "$AGENTS_SRC")"
    if [ -d "$LINK_TARGET" ]; then
        cp -a "$LINK_TARGET"/. "$DEST_AGENTS"/
        ok "Copied existing agents from symlink target $LINK_TARGET → $DEST_AGENTS"
    else
        warn "Symlink target $LINK_TARGET is not a valid directory. Starting fresh."
    fi
elif [ ! -e "$AGENTS_SRC" ]; then
    warn "$AGENTS_SRC does not exist yet. Will create fresh."
    mkdir -p "$COPILOT_HOME"
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 3: Backup ~/.copilot/agents
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 3: Backup original agents directory${RESET}"

BACKUP="$COPILOT_HOME/agents_BACKUP"

if [ -L "$AGENTS_SRC" ]; then
    # Already a symlink — remove it (no data loss, we already copied)
    rm "$AGENTS_SRC"
    ok "Removed existing symlink at $AGENTS_SRC"
elif [ -d "$AGENTS_SRC" ]; then
    if [ -d "$BACKUP" ]; then
        warn "Backup already exists at $BACKUP — skipping mv (data already safe)"
        rm -rf "$AGENTS_SRC"
    else
        mv "$AGENTS_SRC" "$BACKUP"
        ok "Backed up: $AGENTS_SRC → $BACKUP"
    fi
elif [ ! -e "$AGENTS_SRC" ]; then
    info "No existing agents directory to back up."
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 4: Create symlink
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 4: Create symlink${RESET}"

ln -s "$DEST_AGENTS" "$AGENTS_SRC"
ok "Symlink created: $AGENTS_SRC → $DEST_AGENTS"

# Verify
if [ -L "$AGENTS_SRC" ] && [ -d "$AGENTS_SRC" ]; then
    ok "Symlink verified — agents directory is accessible"
else
    die "Symlink verification failed!"
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 5: Locate KB (emulation_agent) and set KB_ROOT
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 5: Locate Knowledge Base (emulation_agent)${RESET}"

KB_ROOT=""

# Option 1: The script is inside the repo already
if [ -f "$REPO_DIR/00_index.md" ]; then
    KB_ROOT="$REPO_DIR"
    ok "Found KB at script's parent directory: $KB_ROOT"
# Option 2: Check common location on working disk
elif [ -f "$WORKING_DISK/emulation_agent/00_index.md" ]; then
    KB_ROOT="$WORKING_DISK/emulation_agent"
    ok "Found KB on working disk: $KB_ROOT"
# Option 3: Home directory
elif [ -f "$HOME/emulation_agent/00_index.md" ]; then
    KB_ROOT="$HOME/emulation_agent"
    ok "Found KB in home directory: $KB_ROOT"
# Option 4: Search NFS disks
else
    info "Searching NFS disks for emulation_agent..."
    FOUND=$(find /nfs/site/disks/*/emulation_agent/00_index.md 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        KB_ROOT="$(dirname "$FOUND")"
        ok "Found KB at: $KB_ROOT"
    else
        err "Could not find emulation_agent automatically."
        echo "  Clone it with: git clone https://github.com/tbaziza/emulation_agent.git"
        read -rp "  Or enter the path manually: " KB_ROOT
        [ ! -f "$KB_ROOT/00_index.md" ] && die "Invalid KB path — 00_index.md not found in $KB_ROOT"
        ok "Using user-provided KB path: $KB_ROOT"
    fi
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Step 6: Copy agent file and update KB_ROOT
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Step 6: Install agent and configure KB_ROOT${RESET}"

AGENT_SRC="$KB_ROOT/copilot_cli_agent/$AGENT_FILE"

if [ ! -f "$AGENT_SRC" ]; then
    die "Agent file not found: $AGENT_SRC"
fi

# Copy agent file to the agents directory
cp "$AGENT_SRC" "$DEST_AGENTS/$AGENT_FILE"
ok "Copied agent: $AGENT_SRC → $DEST_AGENTS/$AGENT_FILE"

# Update KB_ROOT in the agent file — replace the "Find the Knowledge Base" section
# with a hardcoded path so the agent doesn't need to search at runtime
INSTALLED_AGENT="$DEST_AGENTS/$AGENT_FILE"

# Insert a hardcoded KB_ROOT line right after "### 3. Find the Knowledge Base"
sed -i "/### 3\. Find the Knowledge Base/,/> \*\*To clone the KB:\*\*/{
    /### 3\. Find the Knowledge Base/!{
        /> \*\*To clone the KB:\*\*/!d
    }
}" "$INSTALLED_AGENT"

sed -i "s|### 3\. Find the Knowledge Base|### 3. Find the Knowledge Base\n\n**KB_ROOT is pre-configured by init_agent.sh.**\n\nSet \`KB_ROOT=$KB_ROOT\` — no need to search.\n|" "$INSTALLED_AGENT"

# Also replace the generic $KB_ROOT clone instruction
sed -i "s|> \*\*To clone the KB:\*\*.*|> **KB_ROOT = \`$KB_ROOT\`** (configured by init_agent.sh)|" "$INSTALLED_AGENT"

ok "Updated KB_ROOT in agent file → $KB_ROOT"

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Summary
#───────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   ✅  Setup Complete!                                ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}Agents directory:${RESET}  $DEST_AGENTS"
echo -e "  ${CYAN}Symlink:${RESET}           $AGENTS_SRC → $DEST_AGENTS"
echo -e "  ${CYAN}Backup:${RESET}            $BACKUP"
echo -e "  ${CYAN}KB_ROOT:${RESET}           $KB_ROOT"
echo -e "  ${CYAN}Agent installed:${RESET}   $INSTALLED_AGENT"
echo ""
echo -e "  ${GREEN}The sle_emulation_agent is now available in Copilot CLI.${RESET}"
echo -e "  To verify, run: ${BOLD}ls -la ~/.copilot/agents/$AGENT_FILE${RESET}"
echo ""
