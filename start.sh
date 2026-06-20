#!/bin/bash

# ===== Configuration =====
MC_VERSION="26.1.2"   # ← Minecraft version. Change this to switch Forge/MC versions.
# ==========================

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║  🎮  Minecraft Forge Server - Codespaces     ║"
echo "║      Minecraft ${MC_VERSION} (Forge)              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ===== Install jq if missing =====
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}[+] Installing jq...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y jq -qq
    echo -e "${GREEN}[✓] jq installed${NC}"
fi

# ===== Helper: valid binary = file exists and is bigger than threshold =====
is_valid_binary() {
    local f="$1"
    local min_size="${2:-1000000}"
    local size
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ -f "$f" ] && [ "$size" -gt "$min_size" ]
}

# ===== Install Forge server (only if not already installed) =====
if [ -f "run.sh" ] && [ -d "libraries" ]; then
    echo -e "${GREEN}[✓] Forge server already installed${NC}"
else
    echo -e "${YELLOW}[+] Resolving latest Forge build for Minecraft ${MC_VERSION}...${NC}"

    FORGE_BUILD=$(curl -sf "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" \
        | jq -r --arg v "$MC_VERSION" '.promos[$v + "-latest"] // empty')

    if [ -z "$FORGE_BUILD" ]; then
        echo -e "${RED}[✗] Could not resolve a Forge build for MC ${MC_VERSION}.${NC}"
        echo -e "${YELLOW}    Check available versions at https://files.minecraftforge.net/${NC}"
        exit 1
    fi

    FORGE_FULL="${MC_VERSION}-${FORGE_BUILD}"
    echo -e "${GREEN}[✓] Forge ${FORGE_FULL}${NC}"

    INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_FULL}/forge-${FORGE_FULL}-installer.jar"
    echo -e "${YELLOW}[+] Downloading Forge installer...${NC}"
    curl -L "$INSTALLER_URL" -o forge-installer.jar --progress-bar

    if ! is_valid_binary "forge-installer.jar" 500000; then
        echo -e "${RED}[✗] Forge installer download failed!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[+] Installing Forge server (downloads ~150-300MB of libraries, please wait)...${NC}"
    java -jar forge-installer.jar --installServer

    if [ ! -f "run.sh" ]; then
        echo -e "${RED}[✗] Forge installation failed — run.sh was not created.${NC}"
        exit 1
    fi
    chmod +x run.sh

    # Set sane default memory args (Codespace default machine: 2-core/8GB)
    printf '%s\n' "-Xmx2G" "-Xms1G" > user_jvm_args.txt

    echo -e "${GREEN}[✓] Forge server installed${NC}"
fi

# ===== Accept EULA =====
echo "eula=true" > eula.txt
echo -e "${GREEN}[✓] EULA accepted${NC}"

# ===== Create server.properties if missing =====
if [ ! -f "server.properties" ]; then
    cat > server.properties << 'EOF'
server-port=25565
max-players=10
online-mode=false
difficulty=normal
gamemode=survival
level-seed=
level-name=world
motd=\u00A7a\u00A7lMy Codespace Forge Server
pvp=true
allow-flight=true
spawn-protection=16
view-distance=10
simulation-distance=10
spawn-monsters=true
spawn-animals=true
enable-command-block=true
EOF
    echo -e "${GREEN}[✓] server.properties created${NC}"
else
    echo -e "${GREEN}[✓] server.properties already exists${NC}"
fi

# ===== Mods folder =====
mkdir -p mods
MOD_COUNT=$(find mods -maxdepth 1 -name "*.jar" 2>/dev/null | wc -l)
if [ "$MOD_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}[i] No mods in mods/ — drop .jar files there and restart to load them.${NC}"
else
    echo -e "${GREEN}[✓] ${MOD_COUNT} mod(s) loaded from mods/${NC}"
fi

# ===== Download playit.gg (CLI + daemon) =====
if is_valid_binary "./playit-cli" && is_valid_binary "./playitd"; then
    echo -e "${GREEN}[✓] playit already installed${NC}"
else
    echo -e "${YELLOW}[+] Downloading playit.gg...${NC}"

    curl -L "https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-cli-linux-amd64" \
        -o playit-cli --progress-bar
    chmod +x playit-cli

    curl -L "https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-linux-amd64" \
        -o playitd --progress-bar
    chmod +x playitd

    if ! is_valid_binary "./playit-cli" || ! is_valid_binary "./playitd"; then
        echo -e "${RED}[✗] playit download failed!${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] playit installed${NC}"
fi

# ===== Start Minecraft Server =====
echo ""
# Kill any existing server instance (tracked via PID file)
if [ -f mc.pid ] && kill -0 "$(cat mc.pid)" 2>/dev/null; then
    echo -e "${YELLOW}[!] Stopping existing server instance...${NC}"
    kill "$(cat mc.pid)"
    sleep 5
fi
rm -f world/session.lock

echo -e "${YELLOW}[+] Starting Forge server...${NC}"
bash run.sh nogui &
MC_PID=$!
echo "$MC_PID" > mc.pid

echo -e "${YELLOW}[⏳] Waiting for server to fully start (mods can take a few minutes)...${NC}"
TIMEOUT=300
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f logs/latest.log ] && grep -q "Done (" logs/latest.log 2>/dev/null; then
        STARTED=true
        break
    fi
    if ! kill -0 "$MC_PID" 2>/dev/null; then
        echo ""
        echo -e "${RED}[✗] Server crashed during startup! Check logs/latest.log${NC}"
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo -ne "${CYAN}.${NC}"
done
echo ""

if [ "$STARTED" = true ]; then
    echo -e "${GREEN}[✓] Minecraft server is running on port 25565!${NC}"
else
    echo -e "${YELLOW}[!] Still starting after ${TIMEOUT}s — continuing anyway, check logs/latest.log${NC}"
fi
echo ""

# ===== Auto-save every 30 minutes =====
(
    while true; do
        sleep 1800
        echo -e "${YELLOW}[⟳] Auto-saving world + mods to GitHub...${NC}"
        bash save.sh && echo -e "${GREEN}[✓] Auto-save complete${NC}" || echo -e "${RED}[✗] Auto-save failed${NC}"
    done
) &
echo -e "${GREEN}[✓] Auto-save enabled (every 30 min) — run 'bash save.sh' anytime to save manually${NC}"
echo ""

# ===== Start playit.gg tunnel =====
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "${BLUE}[+] Starting playit.gg tunnel...${NC}"
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}  First time? Here's what to do:${NC}"
echo -e "  1. A claim URL will appear below"
echo -e "  2. Open it in your browser"
echo -e "  3. Sign up / log in to playit.gg"
echo -e "  4. Add a Minecraft Java tunnel on port 25565"
echo -e "  5. Your IP:PORT will be shown here ✅"
echo ""
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo ""

export XDG_RUNTIME_DIR=/tmp/playit-run
mkdir -p "$XDG_RUNTIME_DIR"
mkdir -p ~/.config/playit_gg

./playitd --socket-path=./playit.sock --secret-path=~/.config/playit_gg/playit.toml &
sleep 3
./playit-cli --socket-path=./playit.sock
