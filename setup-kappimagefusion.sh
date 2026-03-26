#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# KAppImageFusion — Universal Setup Script
# Installs or uninstalls the KAppImageFusion Dolphin service menu integration.
#
# Usage:
#   ./Setup-KAppImageFusion.sh install
#   ./Setup-KAppImageFusion.sh uninstall
#   ./Setup-KAppImageFusion.sh help
#
# License: GPL-2.0
# -----------------------------------------------------------------------------

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────

log()     { echo -e "${CYAN}[KAppImageFusion]${RESET} $*"; }
success() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source files (relative to this script inside the repo)
SRC_SCRIPT="$SCRIPT_DIR/scripts/appimage-install.sh"
SRC_DESKTOP="$SCRIPT_DIR/servicemenu/appimage-install.desktop"

# Destination paths
DEST_BIN="$HOME/.local/bin"
DEST_SCRIPT="$DEST_BIN/appimage-install.sh"

DEST_SERVICEMENU_5="$HOME/.local/share/kservices5/ServiceMenus"
DEST_SERVICEMENU_6="$HOME/.local/share/kio/servicemenus"
DEST_DESKTOP_5="$DEST_SERVICEMENU_5/appimage-install.desktop"
DEST_DESKTOP_6="$DEST_SERVICEMENU_6/appimage-install.desktop"

# ─── Detect Plasma version ────────────────────────────────────────────────────

detect_plasma() {
    if command -v plasmashell &>/dev/null; then
        PLASMA_VERSION="$(plasmashell --version 2>/dev/null | grep -oP '\d+' | head -n1)"
    else
        PLASMA_VERSION="5"
    fi
    echo "$PLASMA_VERSION"
}

# ─── Detect kbuildsycoca ──────────────────────────────────────────────────────

refresh_kde() {
    log "Refreshing KDE service cache..."
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 --noincremental 2>/dev/null || true
        success "KDE service cache refreshed (Plasma 6)"
    elif command -v kbuildsycoca5 &>/dev/null; then
        kbuildsycoca5 --noincremental 2>/dev/null || true
        success "KDE service cache refreshed (Plasma 5)"
    else
        warn "kbuildsycoca not found. Please restart Dolphin manually."
    fi
}

# ─── Check requirements ───────────────────────────────────────────────────────

check_requirements() {
    local missing=()

    command -v bash        &>/dev/null || missing+=("bash")
    command -v dolphin     &>/dev/null || missing+=("dolphin")
    command -v sed         &>/dev/null || missing+=("sed")
    command -v find        &>/dev/null || missing+=("find")
    command -v notify-send &>/dev/null || warn "notify-send not found — install notifications will be skipped."

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}\nPlease install them and try again."
    fi
}

# ─── Check source files ───────────────────────────────────────────────────────

check_sources() {
    [[ ! -f "$SRC_SCRIPT" ]]  && error "Installer script not found at: $SRC_SCRIPT\nPlease run this script from the root of the KAppImageFusion repository."
    [[ ! -f "$SRC_DESKTOP" ]] && error "Service menu file not found at: $SRC_DESKTOP\nPlease run this script from the root of the KAppImageFusion repository."
}

# ─── INSTALL ──────────────────────────────────────────────────────────────────

cmd_install() {
    header "Installing KAppImageFusion..."

    check_requirements
    check_sources

    PLASMA_VER="$(detect_plasma)"
    log "Detected KDE Plasma version: $PLASMA_VER"

    # ── Install the appimage-install.sh script ──
    log "Installing appimage-install.sh to $DEST_BIN ..."
    mkdir -p "$DEST_BIN"
    cp "$SRC_SCRIPT" "$DEST_SCRIPT"
    chmod +x "$DEST_SCRIPT"
    success "Installer script copied to $DEST_SCRIPT"

    # ── Install the Dolphin service menu .desktop ──
    if [[ "$PLASMA_VER" -ge 6 ]]; then
        log "Installing Dolphin service menu for Plasma 6..."
        mkdir -p "$DEST_SERVICEMENU_6"
        cp "$SRC_DESKTOP" "$DEST_DESKTOP_6"
        chmod +x "$DEST_DESKTOP_6"
        success "Service menu installed to $DEST_DESKTOP_6"
    else
        log "Installing Dolphin service menu for Plasma 5..."
        mkdir -p "$DEST_SERVICEMENU_5"
        cp "$SRC_DESKTOP" "$DEST_DESKTOP_5"
        chmod +x "$DEST_DESKTOP_5"
        success "Service menu installed to $DEST_DESKTOP_5"
    fi

    # ── Refresh KDE ──
    refresh_kde

    echo ""
    echo -e "${GREEN}${BOLD}KAppImageFusion installed successfully!${RESET}"
    echo -e "Right-click any ${BOLD}.AppImage${RESET} file in Dolphin to get started."
    echo ""
}

# ─── UNINSTALL ────────────────────────────────────────────────────────────────

cmd_uninstall() {
    header "Uninstalling KAppImageFusion..."

    local removed=0

    # ── Remove installer script ──
    if [[ -f "$DEST_SCRIPT" ]]; then
        rm -f "$DEST_SCRIPT"
        success "Removed $DEST_SCRIPT"
        removed=$((removed + 1))
    else
        warn "Installer script not found at $DEST_SCRIPT — skipping."
    fi

    # ── Remove Plasma 5 service menu ──
    if [[ -f "$DEST_DESKTOP_5" ]]; then
        rm -f "$DEST_DESKTOP_5"
        success "Removed $DEST_DESKTOP_5"
        removed=$((removed + 1))
    fi

    # ── Remove Plasma 6 service menu ──
    if [[ -f "$DEST_DESKTOP_6" ]]; then
        rm -f "$DEST_DESKTOP_6"
        success "Removed $DEST_DESKTOP_6"
        removed=$((removed + 1))
    fi

    if [[ $removed -eq 0 ]]; then
        warn "No KAppImageFusion files were found. It may not be installed."
        exit 0
    fi

    # ── Refresh KDE ──
    refresh_kde

    echo ""
    echo -e "${GREEN}${BOLD}KAppImageFusion uninstalled successfully.${RESET}"
    echo -e "${YELLOW}Note:${RESET} Any AppImages you previously installed with this tool"
    echo -e "      remain in ${BOLD}~/.local/bin/${RESET} and are not affected."
    echo ""
}

# ─── HELP ─────────────────────────────────────────────────────────────────────

cmd_help() {
    echo ""
    echo -e "${BOLD}KAppImageFusion — Setup Script${RESET}"
    echo -e "Integrates AppImage installation support into the KDE Dolphin file manager."
    echo ""
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  ./Setup-KAppImageFusion.sh ${CYAN}install${RESET}    Install KAppImageFusion"
    echo -e "  ./Setup-KAppImageFusion.sh ${CYAN}uninstall${RESET}  Uninstall KAppImageFusion"
    echo -e "  ./Setup-KAppImageFusion.sh ${CYAN}help${RESET}       Show this help message"
    echo ""
    echo -e "${BOLD}What install does:${RESET}"
    echo -e "  • Copies ${BOLD}appimage-install.sh${RESET} → ~/.local/bin/"
    echo -e "  • Copies ${BOLD}appimage-install.desktop${RESET} → the appropriate KDE ServiceMenus directory"
    echo -e "  • Refreshes the KDE service cache via kbuildsycoca5 or kbuildsycoca6"
    echo ""
    echo -e "${BOLD}What uninstall does:${RESET}"
    echo -e "  • Removes the above two files"
    echo -e "  • Refreshes the KDE service cache"
    echo -e "  • Does ${BOLD}not${RESET} remove any AppImages you have already installed"
    echo ""
    echo -e "${BOLD}File locations:${RESET}"
    echo -e "  Installer script  →  ~/.local/bin/appimage-install.sh"
    echo -e "  Service menu (P5) →  ~/.local/share/kservices5/ServiceMenus/appimage-install.desktop"
    echo -e "  Service menu (P6) →  ~/.local/share/kio/servicemenus/appimage-install.desktop"
    echo ""
    echo -e "${BOLD}Requirements:${RESET}"
    echo -e "  • KDE Plasma 5 or 6 with Dolphin file manager"
    echo -e "  • bash, sed, find"
    echo -e "  • notify-send (optional — for install notifications)"
    echo -e "    Install via: sudo apt install libnotify-bin"
    echo -e "                 sudo pacman -S libnotify"
    echo -e "                 sudo dnf install libnotify"
    echo ""
    echo -e "${BOLD}Project:${RESET}  https://github.com/yourusername/KAppImageFusion"
    echo -e "${BOLD}License:${RESET}  GPL-2.0"
    echo ""
}

# ─── Entry point ──────────────────────────────────────────────────────────────

case "${1:-}" in
    install)   cmd_install   ;;
    uninstall) cmd_uninstall ;;
    help)      cmd_help      ;;
    *)
        echo -e "${RED}[✗]${RESET} Unknown argument: '${1:-}'"
        echo -e "    Run ${BOLD}./Setup-KAppImageFusion.sh help${RESET} for usage information."
        exit 1
        ;;
esac
