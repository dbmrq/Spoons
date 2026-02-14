#!/usr/bin/env bash
#
# Build script for Spoons repository
# Creates .spoon.zip files from Source/ and generates docs/docs.json
#
# Usage:
#   ./build.sh           # Build all Spoons
#   ./build.sh Readline  # Build specific Spoon
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/Source"
OUTPUT_DIR="$SCRIPT_DIR/Spoons"
DOCS_DIR="$SCRIPT_DIR/docs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Build a single Spoon
build_spoon() {
    local spoon_name="$1"
    local source_path="$SOURCE_DIR/${spoon_name}.spoon"
    local output_path="$OUTPUT_DIR/${spoon_name}.spoon.zip"
    
    if [[ ! -d "$source_path" ]]; then
        log_error "Source not found: $source_path"
        return 1
    fi
    
    log_info "Building ${spoon_name}.spoon.zip"
    
    # Create zip (cd into Source to get correct paths)
    (cd "$SOURCE_DIR" && zip -r "$output_path" "${spoon_name}.spoon" -x "*.DS_Store" -x "*/.git/*")
    
    log_info "Created: $output_path"
}

# Generate docs.json from all Spoons
generate_docs() {
    log_info "Generating docs/docs.json"
    
    mkdir -p "$DOCS_DIR"
    
    # Start JSON array
    echo "[" > "$DOCS_DIR/docs.json"
    
    local first=true
    for spoon_dir in "$SOURCE_DIR"/*.spoon; do
        [[ -d "$spoon_dir" ]] || continue
        
        local spoon_name=$(basename "$spoon_dir" .spoon)
        local init_file="$spoon_dir/init.lua"
        
        [[ -f "$init_file" ]] || continue
        
        # Extract metadata from init.lua
        local version=$(grep -o 'obj.version = "[^"]*"' "$init_file" | cut -d'"' -f2 || echo "1.0")
        # Get description: first non-empty line after "--- === SpoonName ===" that starts with ---
        local desc=$(awk '/^--- === .* ===$/{getline; while(/^---$/ || /^--- *$/){getline}; gsub(/^--- */,""); print; exit}' "$init_file")
        local download_url="https://github.com/dbmrq/Spoons/raw/master/Spoons/${spoon_name}.spoon.zip"
        
        if ! $first; then
            echo "," >> "$DOCS_DIR/docs.json"
        fi
        first=false
        
        cat >> "$DOCS_DIR/docs.json" << EOF
  {
    "name": "$spoon_name",
    "version": "$version",
    "desc": "$desc",
    "download_url": "$download_url"
  }
EOF
    done
    
    echo "]" >> "$DOCS_DIR/docs.json"
    
    log_info "Generated: $DOCS_DIR/docs.json"
}

# Main
main() {
    mkdir -p "$OUTPUT_DIR"
    
    if [[ $# -gt 0 ]]; then
        # Build specific Spoons
        for spoon in "$@"; do
            build_spoon "$spoon"
        done
    else
        # Build all Spoons
        for spoon_dir in "$SOURCE_DIR"/*.spoon; do
            [[ -d "$spoon_dir" ]] || continue
            build_spoon "$(basename "$spoon_dir" .spoon)"
        done
    fi
    
    generate_docs
    
    log_info "Build complete!"
}

main "$@"

