#!/bin/bash

# ===== Configuration =====
MC_VERSION="26.1.2"   # change to switch Minecraft versions
# ==========================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

clear

# ===== Install jq if missing =====
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}[+] Installing jq...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y jq -qq
    echo -e "${GREEN}[✓] jq installed${NC}"
fi

# ===== Helper: valid binary = exists and bigger than threshold =====
is_valid_binary() {
    local f="$1"; local min_size="${2:-1000000}"; local size
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ -f "$f" ] && [ "$size" -gt "$min_size" ]
}

# ===== Helper: locate unix_args.txt produced by Forge/NeoForge =====
find_args_file() { find libraries -name "unix_args.txt" 2>/dev/null | head -1; }

# ===== Choose mod loader (only the FIRST time) =====
# Saved in .loader so future runs are non-interactive.
if [ -f .loader ]; then
    LOADER=$(tr -d '[:space:]' < .loader)
    echo -e "${GREEN}[✓] Using saved mod loader: ${LOADER}${NC}"
    echo -e "${YELLOW}    (delete .loader to switch loaders)${NC}"
else
    echo -e "${CYAN}"
    echo "+----------------------------------------------+"
    echo "|   Choose your mod loader (first run)         |"
    echo "+----------------------------------------------+"
    echo -e "${NC}"
    echo -e "  ${GREEN}1)${NC} Fabric    - lightweight, fast, most common"
    echo -e "  ${GREEN}2)${NC} Forge     - largest classic mod ecosystem"
    echo -e "  ${GREEN}3)${NC} NeoForge  - modern fork of Forge"
    echo ""
    if [ -t 0 ]; then
        read -rp "$(echo -e "${YELLOW}Enter 1, 2, or 3 [default: 1]: ${NC}")" LOADER_CHOICE
    else
        LOADER_CHOICE=""
    fi
    case "$LOADER_CHOICE" in
        2) LOADER="forge" ;;
        3) LOADER="neoforge" ;;
        1|"") LOADER="fabric" ;;
        *) echo -e "${YELLOW}[!] Unrecognized '${LOADER_CHOICE}' - defaulting to Fabric.${NC}"
           LOADER="fabric" ;;
    esac
    echo "$LOADER" > .loader
    echo -e "${GREEN}[✓] Mod loader set to: ${LOADER} (saved to .loader)${NC}"
fi

echo -e "${CYAN}"
echo "+----------------------------------------------+"
printf "|  Minecraft %-8s  (%-8s)              |\n" "$MC_VERSION" "$LOADER"
echo "+----------------------------------------------+"
echo -e "${NC}"

# =========================================================================
#  INSTALL - branches per loader
# =========================================================================
case "$LOADER" in

  fabric)
    if is_valid_binary "fabric-server.jar" 50000; then
        echo -e "${GREEN}[✓] Fabric server already installed${NC}"
    else
        echo -e "${YELLOW}[+] Resolving Fabric loader for MC ${MC_VERSION}...${NC}"
        LOADER_VERSION=$(curl -sf "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}" | jq -r '.[0].loader.version // empty')
        if [ -z "$LOADER_VERSION" ]; then
            echo -e "${RED}[✗] No Fabric loader for MC ${MC_VERSION}. See https://fabricmc.net/${NC}"; exit 1
        fi
        echo -e "${GREEN}[✓] Fabric loader ${LOADER_VERSION}${NC}"
        INSTALLER_VERSION=$(curl -sf "https://meta.fabricmc.net/v2/versions/installer" | jq -r '.[0].version // empty')
        if [ -z "$INSTALLER_VERSION" ]; then
            echo -e "${RED}[✗] Could not resolve Fabric installer version.${NC}"; exit 1
        fi
        echo -e "${GREEN}[✓] Fabric installer ${INSTALLER_VERSION}${NC}"
        echo -e "${YELLOW}[+] Downloading Fabric server jar...${NC}"
        curl -L "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER_VERSION}/${INSTALLER_VERSION}/server/jar" -o fabric-server.jar --progress-bar
        # Fabric server launcher is intentionally small (~175 KB); 50 KB is a safe floor.
        if ! is_valid_binary "fabric-server.jar" 50000; then
            echo -e "${RED}[✗] Fabric server download failed!${NC}"; exit 1
        fi
        echo -e "${GREEN}[✓] Fabric server installed ($(du -sh fabric-server.jar | cut -f1))${NC}"
    fi
    ;;

  forge)
    if [ -n "$(find_args_file)" ]; then
        echo -e "${GREEN}[✓] Forge server already installed${NC}"
    else
        echo -e "${YELLOW}[+] Resolving Forge build for MC ${MC_VERSION}...${NC}"
        FORGE_BUILD=$(curl -sf "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" | jq -r --arg v "$MC_VERSION" '.promos[$v+"-recommended"] // .promos[$v+"-latest"] // empty')
        if [ -z "$FORGE_BUILD" ]; then
            echo -e "${RED}[✗] No Forge build for MC ${MC_VERSION}. See https://files.minecraftforge.net/${NC}"; exit 1
        fi
        FORGE_FULL="${MC_VERSION}-${FORGE_BUILD}"
        echo -e "${GREEN}[✓] Forge ${FORGE_FULL}${NC}"
        echo -e "${YELLOW}[+] Downloading Forge installer...${NC}"
        curl -L "https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_FULL}/forge-${FORGE_FULL}-installer.jar" -o forge-installer.jar --progress-bar
        if ! is_valid_binary "forge-installer.jar" 50000; then
            echo -e "${RED}[✗] Forge installer download failed!${NC}"; exit 1
        fi
        echo -e "${YELLOW}[+] Running Forge server installer (downloads MC + libraries)...${NC}"
        java -jar forge-installer.jar --installServer
        if [ -z "$(find_args_file)" ]; then
            echo -e "${RED}[✗] Forge install failed - no unix_args.txt produced.${NC}"; exit 1
        fi
        rm -f forge-installer.jar forge-installer.jar.log
        echo -e "${GREEN}[✓] Forge server installed${NC}"
    fi
    ;;

  neoforge)
    if [ -n "$(find_args_file)" ]; then
        echo -e "${GREEN}[✓] NeoForge server already installed${NC}"
    else
        echo -e "${YELLOW}[+] Resolving NeoForge version for MC ${MC_VERSION}...${NC}"
        ESC_VER="${MC_VERSION//./\\.}"
        NEO_VERSION=$(curl -sf "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" | grep -oP "<version>\K${ESC_VER}\.[0-9]+(?=</version>)" | tail -1)
        if [ -z "$NEO_VERSION" ]; then
            echo -e "${RED}[✗] No NeoForge build for MC ${MC_VERSION}. See https://neoforged.net/${NC}"; exit 1
        fi
        echo -e "${GREEN}[✓] NeoForge ${NEO_VERSION}${NC}"
        echo -e "${YELLOW}[+] Downloading NeoForge installer...${NC}"
        curl -L "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VERSION}/neoforge-${NEO_VERSION}-installer.jar" -o neoforge-installer.jar --progress-bar
        if ! is_valid_binary "neoforge-installer.jar" 50000; then
            echo -e "${RED}[✗] NeoForge installer download failed!${NC}"; exit 1
        fi
        echo -e "${YELLOW}[+] Running NeoForge server installer (downloads MC + libraries)...${NC}"
        java -jar neoforge-installer.jar --installServer
        if [ -z "$(find_args_file)" ]; then
            echo -e "${RED}[✗] NeoForge install failed - no unix_args.txt produced.${NC}"; exit 1
        fi
        rm -f neoforge-installer.jar neoforge-installer.jar.log
        echo -e "${GREEN}[✓] NeoForge server installed${NC}"
    fi
    ;;

  *)
    echo -e "${RED}[✗] Unknown loader '${LOADER}' in .loader file.${NC}"; exit 1
    ;;
esac

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
motd=\u00A7a\u00A7lMy Codespace Server
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
    echo -e "${YELLOW}[i] No mods in mods/ - drop .jar files there and restart to load them.${NC}"
    [ "$LOADER" = "fabric" ] && echo -e "${YELLOW}    Most Fabric mods also need Fabric API - modrinth.com/mod/fabric-api${NC}"
else
    echo -e "${GREEN}[✓] ${MOD_COUNT} mod(s) loaded from mods/${NC}"
fi

# ===== Download playit.gg (CLI + daemon) =====
if is_valid_binary "./playit-cli" && is_valid_binary "./playitd"; then
    echo -e "${GREEN}[✓] playit already installed${NC}"
else
    echo -e "${YELLOW}[+] Downloading playit.gg...${NC}"
    curl -L "https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-cli-linux-amd64" -o playit-cli --progress-bar
    chmod +x playit-cli
    curl -L "https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-linux-amd64" -o playitd --progress-bar
    chmod +x playitd
    if ! is_valid_binary "./playit-cli" || ! is_valid_binary "./playitd"; then
        echo -e "${RED}[✗] playit download failed!${NC}"; exit 1
    fi
    echo -e "${GREEN}[✓] playit installed${NC}"
fi

# ===== Build launch command for the chosen loader =====
if [ "$LOADER" = "fabric" ]; then
    LAUNCH=(java -Xmx2G -Xms1G -jar fabric-server.jar nogui)
else
    ARGS_FILE=$(find_args_file)
    LAUNCH=(java -Xmx2G -Xms1G "@${ARGS_FILE}" nogui)
fi

# ===== Start Minecraft Server =====
echo ""
if [ -f mc.pid ] && kill -0 "$(cat mc.pid)" 2>/dev/null; then
    echo -e "${YELLOW}[!] Stopping existing server instance...${NC}"
    kill "$(cat mc.pid)"; sleep 5
fi
rm -f world/session.lock

echo -e "${YELLOW}[+] Starting ${LOADER} server...${NC}"
"${LAUNCH[@]}" &
MC_PID=$!
echo "$MC_PID" > mc.pid

echo -e "${YELLOW}[...] Waiting for server to fully start...${NC}"
TIMEOUT=180; ELAPSED=0; STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f logs/latest.log ] && grep -q "Done (" logs/latest.log 2>/dev/null; then
        STARTED=true; break
    fi
    if ! kill -0 "$MC_PID" 2>/dev/null; then
        echo ""; echo -e "${RED}[✗] Server crashed during startup! Check logs/latest.log${NC}"; exit 1
    fi
    sleep 2; ELAPSED=$((ELAPSED + 2)); echo -ne "${CYAN}.${NC}"
done
echo ""

if [ "$STARTED" = true ]; then
    echo -e "${GREEN}[✓] Minecraft server is running on port 25565!${NC}"
else
    echo -e "${YELLOW}[!] Still starting after ${TIMEOUT}s - continuing, check logs/latest.log${NC}"
fi
echo ""

# ===== Auto-save every 30 minutes =====
(
    while true; do
        sleep 1800
        echo -e "${YELLOW}[auto] Saving world + mods to GitHub...${NC}"
        bash save.sh && echo -e "${GREEN}[✓] Auto-save complete${NC}" || echo -e "${RED}[✗] Auto-save failed${NC}"
    done
) &
echo -e "${GREEN}[✓] Auto-save enabled (every 30 min) - run 'bash save.sh' to save manually${NC}"
echo ""

# ===== Start playit.gg tunnel =====
echo -e "${CYAN}=====================================${NC}"
echo -e "${BLUE}[+] Starting playit.gg tunnel...${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""
echo -e "${YELLOW}  First time? Here's what to do:${NC}"
echo -e "  1. A claim URL will appear below"
echo -e "  2. Open it in your browser"
echo -e "  3. Sign up / log in to playit.gg"
echo -e "  4. Add a Minecraft Java tunnel on port 25565"
echo -e "  5. Your IP:PORT will be shown here"
echo ""

export XDG_RUNTIME_DIR=/tmp/playit-run
mkdir -p "$XDG_RUNTIME_DIR"
mkdir -p "$HOME/.config/playit_gg"

./playitd --socket-path=./playit.sock --secret-path="$HOME/.config/playit_gg/playit.toml" &
sleep 3
./playit-cli --socket-path=./playit.sock
