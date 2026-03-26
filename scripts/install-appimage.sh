#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# KAppImageFusion — AppImage Installer Script
# Extracts the embedded .desktop and icon from an AppImage, patches the Exec=
# and Icon= lines to point to the installed location, copies everything into
# the appropriate KDE directories, and refreshes the desktop database.
#
# Usage:
#   appimage-install.sh [--run] <path-to-appimage>
#
# License: GPL-2.0
# -----------------------------------------------------------------------------

set -euo pipefail

# ─── Helpers ──────────────────────────────────────────────────────────────────

log()    { echo "[KAppImageFusion] $*"; }
ok()     { notify-send "KAppImageFusion" "$*" --icon=dialog-information 2>/dev/null || true; }
err()    { notify-send "KAppImageFusion" "$*" --icon=dialog-error 2>/dev/null || true; echo "[ERROR] $*" >&2; exit 1; }

# ─── Argument parsing ─────────────────────────────────────────────────────────

RUN=false
APPIMAGE_SRC=""

for arg in "$@"; do
    case "$arg" in
        --run) RUN=true ;;
        *)     APPIMAGE_SRC="$arg" ;;
    esac
done

[[ -z "$APPIMAGE_SRC" ]]       && err "No AppImage path provided."
[[ ! -f "$APPIMAGE_SRC" ]]     && err "File not found: $APPIMAGE_SRC"
[[ ! -r "$APPIMAGE_SRC" ]]     && err "Cannot read file: $APPIMAGE_SRC"

# ─── Paths ────────────────────────────────────────────────────────────────────

APPIMAGE_SRC="$(realpath "$APPIMAGE_SRC")"
BASENAME="$(basename "$APPIMAGE_SRC")"
APPNAME="${BASENAME%.AppImage}"
APPNAME="${APPNAME%.appimage}"

BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons"
TEMP_DIR="$(mktemp -d /tmp/kappfusion-XXXXXX)"

APPIMAGE_DEST="$BIN_DIR/$BASENAME"

# ─── Cleanup on exit ──────────────────────────────────────────────────────────

cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# ─── Step 1: Create required directories ──────────────────────────────────────

mkdir -p "$BIN_DIR" "$APPS_DIR"

# ─── Step 2: Copy AppImage to ~/.local/bin ────────────────────────────────────

if [[ "$APPIMAGE_SRC" != "$APPIMAGE_DEST" ]]; then
    log "Copying $BASENAME to $BIN_DIR ..."
    cp "$APPIMAGE_SRC" "$APPIMAGE_DEST"
fi

chmod +x "$APPIMAGE_DEST"
log "AppImage installed to $APPIMAGE_DEST"

# ─── Step 3: Extract AppImage contents ────────────────────────────────────────

log "Extracting AppImage contents..."
cd "$TEMP_DIR"

# Some AppImages need to be run from their own directory
cp "$APPIMAGE_DEST" "$TEMP_DIR/$BASENAME"
chmod +x "$TEMP_DIR/$BASENAME"

if ! "$TEMP_DIR/$BASENAME" --appimage-extract > /dev/null 2>&1; then
    err "Failed to extract AppImage. The file may be corrupted or not a valid AppImage."
fi

SQUASH_ROOT="$TEMP_DIR/squashfs-root"

[[ ! -d "$SQUASH_ROOT" ]] && err "Extraction failed — squashfs-root directory not found."

# ─── Step 4: Locate the .desktop file ────────────────────────────────────────

log "Locating embedded .desktop file..."

# Prefer .desktop files at the root level first (AppImage standard location)
DESKTOP_FILE=""
DESKTOP_FILE="$(find "$SQUASH_ROOT" -maxdepth 1 -name "*.desktop" | head -n 1)"

# Fall back to usr/share/applications/
if [[ -z "$DESKTOP_FILE" ]]; then
    DESKTOP_FILE="$(find "$SQUASH_ROOT/usr/share/applications" -name "*.desktop" 2>/dev/null | head -n 1)"
fi

[[ -z "$DESKTOP_FILE" ]] && err "No .desktop file found inside the AppImage."
log "Found .desktop: $DESKTOP_FILE"

# ─── Step 5: Locate the best icon ─────────────────────────────────────────────

log "Locating best available icon..."

ICON_SRC=""

# Read the Icon= value from the embedded .desktop
ICON_NAME="$(grep -m1 '^Icon=' "$DESKTOP_FILE" | cut -d= -f2 | tr -d '[:space:]')"

# 1. Prefer SVG from hicolor scalable
if [[ -n "$ICON_NAME" ]]; then
    ICON_SRC="$(find "$SQUASH_ROOT" -path "*/hicolor/scalable/*" -name "${ICON_NAME}.svg" 2>/dev/null | head -n 1)"
fi

# 2. Fall back to any SVG matching the icon name
if [[ -z "$ICON_SRC" ]] && [[ -n "$ICON_NAME" ]]; then
    ICON_SRC="$(find "$SQUASH_ROOT" -name "${ICON_NAME}.svg" 2>/dev/null | head -n 1)"
fi

# 3. Fall back to largest PNG matching the icon name (sort by resolution desc)
if [[ -z "$ICON_SRC" ]] && [[ -n "$ICON_NAME" ]]; then
    ICON_SRC="$(find "$SQUASH_ROOT" -name "${ICON_NAME}.png" 2>/dev/null \
        | sort -t/ -k1 -V -r | head -n 1)"
fi

# 4. Fall back to any PNG at root level
if [[ -z "$ICON_SRC" ]]; then
    ICON_SRC="$(find "$SQUASH_ROOT" -maxdepth 1 -name "*.png" | head -n 1)"
fi

# 5. Last resort — any SVG at root level
if [[ -z "$ICON_SRC" ]]; then
    ICON_SRC="$(find "$SQUASH_ROOT" -maxdepth 1 -name "*.svg" | head -n 1)"
fi

if [[ -z "$ICON_SRC" ]]; then
    log "Warning: No icon found inside the AppImage. The app will use a generic icon."
fi

# ─── Step 6: Install icon ─────────────────────────────────────────────────────

INSTALLED_ICON_NAME="$APPNAME"

if [[ -n "$ICON_SRC" ]]; then
    ICON_EXT="${ICON_SRC##*.}"

    if [[ "$ICON_EXT" == "svg" ]]; then
        ICON_DEST_DIR="$ICONS_DIR/scalable/apps"
    else
        # Detect PNG size and place in the correct hicolor bucket
        PNG_SIZE="256x256"
        if command -v identify &>/dev/null; then
            PNG_SIZE="$(identify -format "%wx%h" "$ICON_SRC" 2>/dev/null || echo "256x256")"
        fi
        ICON_DEST_DIR="$ICONS_DIR/${PNG_SIZE}/apps"
    fi

    mkdir -p "$ICON_DEST_DIR"
    ICON_DEST="$ICON_DEST_DIR/${INSTALLED_ICON_NAME}.${ICON_EXT}"
    cp "$ICON_SRC" "$ICON_DEST"
    log "Icon installed to $ICON_DEST"
fi

# ─── Step 7: Patch and install the .desktop file ──────────────────────────────

log "Patching .desktop file..."

DESKTOP_DEST="$APPS_DIR/${APPNAME}.desktop"
cp "$DESKTOP_FILE" "$DESKTOP_DEST"

# Patch Exec= line — replace whatever is there with the installed AppImage path
# Preserve any arguments like %U or %F that may follow the original executable
EXEC_ARGS="$(grep -m1 '^Exec=' "$DESKTOP_DEST" | sed 's/^Exec=[^ ]*//' | tr -d '\n')"
sed -i "s|^Exec=.*|Exec=${APPIMAGE_DEST}${EXEC_ARGS}|" "$DESKTOP_DEST"

# Patch Icon= line — point to our installed icon name
sed -i "s|^Icon=.*|Icon=${INSTALLED_ICON_NAME}|" "$DESKTOP_DEST"

# Ensure the desktop file is marked as trusted by KDE
chmod +x "$DESKTOP_DEST"

log "Desktop file installed to $DESKTOP_DEST"

# ─── Step 8: Refresh KDE desktop database ────────────────────────────────────

log "Refreshing KDE desktop database..."

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

if command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 --noincremental 2>/dev/null || true
elif command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental 2>/dev/null || true
fi

# ─── Step 9: Notify and optionally run ───────────────────────────────────────

APP_DISPLAY_NAME="$(grep -m1 '^Name=' "$DESKTOP_DEST" | cut -d= -f2)"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-$APPNAME}"

ok "$APP_DISPLAY_NAME installed successfully!"
log "Done! $APP_DISPLAY_NAME is now available in your KDE application menu."

if $RUN; then
    log "Launching $APP_DISPLAY_NAME ..."
    "$APPIMAGE_DEST" &
fi
