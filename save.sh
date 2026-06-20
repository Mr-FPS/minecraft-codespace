#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}💾 Saving world + mods to GitHub...${NC}"

# ===== Ensure .gitignore is set up =====
if [ ! -f .gitignore ] || ! grep -q "^libraries/" .gitignore 2>/dev/null; then
    cat > .gitignore << 'EOF'
forge-installer.jar
libraries/
logs/
crash-reports/
*.log
run.sh
run.bat
user_jvm_args.txt
playit-cli
playitd
playit.sock
mc.pid
world/session.lock
EOF
    echo -e "${GREEN}[✓] .gitignore set up${NC}"
fi

# ===== Archive the world (avoids committing thousands of tiny chunk files) =====
if [ -d world ]; then
    echo -e "${YELLOW}[+] Archiving world/...${NC}"
    tar --exclude='session.lock' -czf world.tar.gz world/
    echo -e "${GREEN}[✓] world.tar.gz created ($(du -sh world.tar.gz | cut -f1))${NC}"
else
    echo -e "${YELLOW}[i] No world/ folder yet — server hasn't generated one.${NC}"
fi

# ===== Stage everything important =====
git add world.tar.gz \
        mods/ \
        server.properties \
        eula.txt \
        ops.json \
        whitelist.json \
        banned-players.json \
        banned-ips.json \
        .gitignore \
        2>/dev/null

if git diff --cached --quiet; then
    echo -e "${YELLOW}[i] Nothing new to save.${NC}"
    exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
git commit -m "💾 Save — ${TIMESTAMP}"

if git push; then
    echo -e "${GREEN}[✓] Saved to GitHub at ${TIMESTAMP}${NC}"
else
    echo -e "${RED}[✗] Push failed. Check 'git remote -v' and that you have write access.${NC}"
    exit 1
fi
