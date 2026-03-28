#!/usr/bin/env bash
set -euo pipefail

# Color functions using ANSI codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Parse arguments
AUTO=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)
      AUTO=true
      shift
      ;;
    *)
      echo "Usage: $0 [--auto]"
      exit 1
      ;;
  esac
done

if [[ "$AUTO" == true ]]; then
  export DEBIAN_FRONTEND=noninteractive
fi

# Step 1: apt update
echo -e "${BLUE}Running apt update...${RESET}"
sudo apt update

# Step 2: apt upgrade
echo -e "${BLUE}Running apt upgrade...${RESET}"
sudo apt upgrade -y

# Step 3: apt autoremove
echo -e "${BLUE}Running apt autoremove...${RESET}"
sudo apt autoremove -y

# Step 4: apt autoclean
echo -e "${BLUE}Running apt autoclean...${RESET}"
sudo apt autoclean

# Step 5: pip3 outdated check
if command -v pip3 >/dev/null 2>&1; then
  echo -e "${YELLOW}Checking for outdated pip3 packages...${RESET}"
  pip3 list --outdated
else
  echo -e "${YELLOW}pip3 not found, skipping...${RESET}"
fi

# Summary
echo -e "${GREEN}Package update complete.${RESET}"
exit 0
