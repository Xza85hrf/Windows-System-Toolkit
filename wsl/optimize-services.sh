#!/usr/bin/env bash
set -euo pipefail

SERVICES=(
  "cloud-init"
  "cloud-init-local"
  "snapd"
  "snapd.socket"
  "snapd.seeded"
  "landscape-client"
  "apport"
)

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

disabled_count=0
skipped_count=0
not_found_count=0

echo -e "${BLUE}=== Optimizing WSL Services ===${NC}"

for service in "${SERVICES[@]}"; do
  if systemctl list-unit-files "$service" &>/dev/null; then
    if systemctl is-enabled "$service" &>/dev/null; then
      echo -e "${YELLOW}Disabling $service...${NC}"
      if sudo systemctl disable --now "$service" 2>/dev/null; then
        echo -e "${GREEN}$service disabled successfully${NC}"
        ((disabled_count++))
      else
        echo -e "${RED}Failed to disable $service${NC}"
        ((skipped_count++))
      fi
    else
      echo -e "${GREEN}$service already disabled${NC}"
      ((skipped_count++))
    fi
  else
    echo -e "${BLUE}$service not installed (skip)${NC}"
    ((not_found_count++))
  fi
done

echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Disabled: ${GREEN}$disabled_count${NC}"
echo -e "Already disabled: ${YELLOW}$skipped_count${NC}"
echo -e "Not found: ${BLUE}$not_found_count${NC}"

exit 0
