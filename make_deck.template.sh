#!/usr/bin/env bash

# make_deck - A truly standalone pandoc beamer presentation generator
# Usage: make_deck input.md output.pdf [--theme THEME] [--theme-file NAME]
#        make_deck --import-theme template.pptx [--name mytheme]

set -e

# Configuration
SOURCE_FORMAT="markdown_strict+pipe_tables+backtick_code_blocks+auto_identifiers+strikeout+yaml_metadata_block+implicit_figures+all_symbols_escapable+link_attributes+smart+fenced_divs"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create embedded template file
create_template() {
    local temp_dir="$1"

    # Create the simple beamer template
    cat > "$temp_dir/simple_beamer.latex" << 'TEMPLATE_EOF'
__SIMPLE_BEAMER_CONTENT__
TEMPLATE_EOF
}

# Function to create embedded Python extractor
create_extractor() {
    local temp_dir="$1"

    cat > "$temp_dir/extract_pptx_theme.py" << 'EXTRACTOR_EOF'
__EXTRACT_PPTX_THEME_CONTENT__
EXTRACTOR_EOF
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: make_deck input.md output.pdf [OPTIONS]
       make_deck --import-theme template.pptx [--name mytheme]

A portable pandoc beamer presentation generator.

Build mode:
  input.md         Input Markdown file
  output.pdf       Output PDF file
  --theme THEME    Beamer theme name (default: default)
  --theme-file NAME  Apply a saved color theme from ~/.make_deck/themes/

Import mode:
  --import-theme FILE  Extract colors/fonts from a .pptx file
  --name NAME          Theme name (default: derived from filename)

Available beamer themes:
  AnnArbor, Antibes, Bergen, Berkeley, Berlin, Boadilla, CambridgeUS,
  Copenhagen, Darmstadt, Dresden, Frankfurt, Goettingen, Hannover,
  Ilmenau, JuanLesPins, Luebeck, Madrid, Malmoe, Marburg, Montpellier,
  PaloAlto, Pittsburgh, Rochester, Singapore, Szeged, Warsaw, boxes, default

Examples:
  make_deck presentation.md presentation.pdf
  make_deck slides.md slides.pdf --theme Copenhagen
  make_deck --import-theme corporate.pptx --name corporate
  make_deck slides.md slides.pdf --theme-file corporate

Requirements:
  - pandoc
  - python3 (for --import-theme only)
  - One of: tectonic, lualatex, xelatex
EOF
}

# ── Argument parsing ──────────────────────────────────────────────

# Check for help flag early
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Detect mode: import or build
MODE="build"
IMPORT_FILE=""
THEME_NAME=""
INPUT_FILE=""
OUTPUT_FILE=""
THEME="default"
THEME_FILE=""

if [ "$1" = "--import-theme" ]; then
    MODE="import"
    shift
    IMPORT_FILE="$1"
    shift || true
    # Parse remaining import-mode flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                THEME_NAME="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option '$1' in import mode" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done
else
    # Build mode: first two positional args are input and output
    if [ $# -lt 2 ]; then
        echo "Error: Missing required arguments." >&2
        show_usage >&2
        exit 1
    fi
    INPUT_FILE="$1"
    OUTPUT_FILE="$2"
    shift 2
    # Parse remaining build-mode flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --theme)
                THEME="$2"
                shift 2
                ;;
            --theme-file)
                THEME_FILE="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done
fi

# ── Import mode ───────────────────────────────────────────────────

if [ "$MODE" = "import" ]; then
    if [ -z "$IMPORT_FILE" ]; then
        echo "Error: No .pptx file specified." >&2
        show_usage >&2
        exit 1
    fi

    if [ ! -f "$IMPORT_FILE" ]; then
        echo "Error: File not found: $IMPORT_FILE" >&2
        exit 1
    fi

    if ! command_exists python3; then
        echo "Error: python3 is required for --import-theme." >&2
        exit 1
    fi

    # Derive theme name from filename if not provided
    if [ -z "$THEME_NAME" ]; then
        THEME_NAME=$(basename "$IMPORT_FILE" .pptx)
        # Lowercase and replace non-alnum with underscores
        THEME_NAME=$(echo "$THEME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    fi

    THEMES_DIR="$HOME/.make_deck/themes"
    mkdir -p "$THEMES_DIR"

    # Write embedded extractor to temp file
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf '$TEMP_DIR'" EXIT
    create_extractor "$TEMP_DIR"

    OUTPUT_PATH=$(python3 "$TEMP_DIR/extract_pptx_theme.py" "$IMPORT_FILE" --name "$THEME_NAME" --output-dir "$THEMES_DIR")

    echo "Theme extracted: $OUTPUT_PATH"
    echo ""
    echo "Use it with:"
    echo "  make_deck slides.md slides.pdf --theme-file $THEME_NAME"
    exit 0
fi

# ── Build mode ────────────────────────────────────────────────────

# Validate input file
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found." >&2
    exit 1
fi

# Check for required dependencies
if ! command_exists pandoc; then
    echo "Error: pandoc is not installed or not in PATH." >&2
    echo "Install with: brew install pandoc (macOS) or see https://pandoc.org/installing.html" >&2
    exit 1
fi

# Choose a PDF engine
PDF_ENGINE=""
if command_exists tectonic; then
    PDF_ENGINE="tectonic"
elif command_exists lualatex; then
    PDF_ENGINE="lualatex"
elif command_exists xelatex; then
    PDF_ENGINE="xelatex"
else
    echo "Error: No TeX engine found (tectonic/lualatex/xelatex)." >&2
    echo "Install one of:" >&2
    echo "  - tectonic: brew install tectonic (recommended on macOS)" >&2
    echo "  - TeX distribution: brew install --cask mactex-no-gui" >&2
    exit 1
fi

echo "Using PDF engine: $PDF_ENGINE"

# Get current date
DATE_COVER=$(date "+%d %B %Y")

# Create temporary directory for templates
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# Create embedded template
create_template "$TEMP_DIR"

# Build pandoc command using templates from temp directory
PANDOC_CMD=(
    pandoc
    -s
    --dpi=300
    --slide-level 2
    --toc
    --listings
    --shift-heading-level=0
    --template "$TEMP_DIR/simple_beamer.latex"
    --pdf-engine "$PDF_ENGINE"
    -f "$SOURCE_FORMAT"
    -M "date=$DATE_COVER"
    -V classoption:aspectratio=169
    -V theme="$THEME"
    --highlight-style=tango
    -t beamer
    "$INPUT_FILE"
    -o "$OUTPUT_FILE"
)

# Apply custom theme file if specified
if [ -n "$THEME_FILE" ]; then
    RESOLVED_THEME_FILE="$HOME/.make_deck/themes/$THEME_FILE.latex"
    if [ ! -f "$RESOLVED_THEME_FILE" ]; then
        echo "Error: Theme file not found: $RESOLVED_THEME_FILE" >&2
        echo "Import a theme first with: make_deck --import-theme template.pptx --name $THEME_FILE" >&2
        exit 1
    fi
    PANDOC_CMD+=(-H "$RESOLVED_THEME_FILE")
fi

# Execute pandoc command
echo "Generating PDF: $OUTPUT_FILE"
"${PANDOC_CMD[@]}"

if [ $? -eq 0 ]; then
    echo "Successfully generated: $OUTPUT_FILE"
else
    echo "Error: Failed to generate PDF" >&2
    exit 1
fi
