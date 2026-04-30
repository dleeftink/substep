#!/bin/bash
# Concatenates SQL files in topological order for BigQuery installation

# to run: ./scripts/build_install.sh
# windows: tr -d '\r' < ./scripts/build_install.sh | bash

OUTPUT_FILE="bq/app/install.sql"
MINIFY=false # Default to false for safer debugging
mkdir -p bq/app

# Parse CLI arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--minify) MINIFY=true ;;
        -h|--help) 
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -m, --minify    Enable SQL minification (string-safe)"
            echo "  -h, --help      Show this help menu"
            exit 0
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Clear and initialize output file
echo "-- Generated BigQuery Install Script" > "$OUTPUT_FILE"

# Run Python script to generate dependencies.yaml
python3 scripts/topo_sort.py

if [ ! -f "bq/app/dependencies.yaml" ]; then
    echo "Error: Topological sort failed to generate dependencies.yaml."
    exit 1
fi

# We can use python to read the yaml safely instead of needing 'yq'
# This iterates through the install order and looks up the path in the path_map
mapfile -t INSTALL_ORDER < <(python3 -c "import yaml; print('\n'.join(yaml.safe_load(open('bq/dependency.yaml'))['install_order']))")

# Function to get path from function name
get_path() {
    local func_name=$1
    python3 -c "import yaml; print(yaml.safe_load(open('bq/dependency.yaml'))['path_map'].get('$func_name', ''))"
}

# Function to clean, minify, and append
append_clean_sql() {
    local file_path=$1
    echo -e "\n-- Source: $file_path" >> "$OUTPUT_FILE"
    
    if [ "$MINIFY" = true ]; then
        # MINIFICATION WITH STRING PROTECTION:
        perl -0777 -pe '
            s/\/\*.*?\*\///gs; 
            s/--.*//g;
            s/(["\x27])(?:\\.|(?!\1).)*\1(*SKIP)(*F)|(?:\s+)/ /g;
            s/(["\x27])(?:\\.|(?!\1).)*\1(*SKIP)(*F)|\s*([,()=+\-*\/])\s*/$2/g;
            s/;\s*$//;
        ' "$file_path" >> "$OUTPUT_FILE"
    else
        # Just strip comments and trailing semicolons
        perl -0777 -pe 's/\/\*.*?\*\///gs; s/--.*//g' "$file_path" | \
        sed -e 's/[[:space:];]*$//' >> "$OUTPUT_FILE"
    fi
    
    echo -e ";" >> "$OUTPUT_FILE"
}

echo -e "\n-- META FUNCTIONS" >> "$OUTPUT_FILE"
for func in "${INSTALL_ORDER[@]}"; do
    if [[ "$func" == *"_meta.sql"* ]]; then
        append_clean_sql "$(get_path "$func")"
    fi
done

echo -e "\n-- CORE FUNCTIONS (DEPENDENCY ORDER)" >> "$OUTPUT_FILE"
for func in "${INSTALL_ORDER[@]}"; do
    if [[ "$func" != *"_meta.sql"* ]]; then
        append_clean_sql "$(get_path "$func")"
    fi
done

echo "Install file generated: $OUTPUT_FILE (Minify: $MINIFY)"
