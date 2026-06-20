#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   📥  Importing World + Mods from GitHub     ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}[+] Pulling latest data from GitHub...${NC}"
git pull

# ===== Restore world =====
if [ -f world.tar.gz ]; then
    if [ -d world ] && [ "$(find world -mindepth 1 2>/dev/null | head -1)" ]; then
        echo -e "${YELLOW}[!] A local world/ folder already has data — skipping restore${NC}"
        echo -e "${YELLOW}    to avoid overwriting it. Run 'rm -rf world' first if you${NC}"
        echo -e "${YELLOW}    want to restore the saved version instead.${NC}"
    else
        echo -e "${YELLOW}[+] Extracting world.tar.gz...${NC}"
        tar -xzf world.tar.gz
        echo -e "${GREEN}[✓] World restored ($(du -sh world | cut -f1))${NC}"
    fi
else
    echo -e "${YELLOW}[i] No world.tar.gz found in the repo yet — nothing to restore.${NC}"
fi

# ===== Check mods =====
mkdir -p mods
MOD_COUNT=$(find mods -maxdepth 1 -name "*.jar" 2>/dev/null | wc -l)
if [ "$MOD_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[✓] ${MOD_COUNT} mod(s) found:${NC}"
    find mods -maxdepth 1 -name "*.jar" -exec basename {} \; | sed 's/^/    - /'
else
    echo -e "${YELLOW}[i] No mods found in mods/.${NC}"
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "${GREEN}[✓] Import complete!${NC}"
echo -e "${YELLOW}    Now run: bash start.sh${NC}"
echo -e "${CYAN}══════════════════════════════════════${NC}"
