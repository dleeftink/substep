#!/bin/bash
# Concatenates SQL files in topological order for BigQuery installation

# to run: ./scripts/build_install.sh
# windows: tr -d '\r' < ./scripts/build_install.sh | bash

OUTPUT_FILE="bq/app/install.sql"
MINIFY=false
EXCLUDED_NAMESPACES="app,try"
mkdir -p bq/app

# Parse CLI arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--minify) 
            MINIFY=true 
            shift  # This moves $2 into the $1 position
            ;;
        -e|--excluded-namespaces) 
            EXCLUDED_NAMESPACES="$2"
            shift 2
            ;;
        -h|--help) 
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -m, --minify            Enable SQL minification"
            echo "  -e, --excluded-namespaces  Comma-separated list of namespaces to exclude (default: $EXCLUDED_NAMESPACES)"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac

done

get_topological_order() {
    python3 -c "
import yaml, sys
try:
    with open('bq/app/dependencies.yaml') as f:
        data = yaml.safe_load(f)
        for func in data['install_order']:
            print(f\"{data['path_map'][func]}|{func}\")
except Exception as e:
    print(f'Error reading dependencies: {e}', file=sys.stderr)
    sys.exit(1)
"
}

append_clean_sql() {
    local file_path=$1
    echo -e "\n-- Source: $file_path" >> "$OUTPUT_FILE"
    
    if [ "$MINIFY" = true ]; then
        perl -0777 -pe '
            s/\/\*.*?\*\///gs; 
            s/--.*//g;
            s/(["\x27])(?:\\.|(?!\1).)*\1(*SKIP)(*F)|(?:\s+)/ /g;
            s/(["\x27])(?:\\.|(?!\1).)*\1(*SKIP)(*F)|\s*([,()=+\-*\/])\s*/$2/g;
            s/;\s*$//;
        ' "$file_path" >> "$OUTPUT_FILE"
    else
        perl -0777 -pe 's/\/\*.*?\*\///gs; s/--.*//g' "$file_path" | \
        sed -e 's/[[:space:];]*$//' >> "$OUTPUT_FILE"
    fi
    echo -e ";" >> "$OUTPUT_FILE"
}

# ---
# Execution
# ---

echo "-- Generated BigQuery Install Script" > "$OUTPUT_FILE"

# Generate dependency file
python3 scripts/topo_sort.py "$EXCLUDED_NAMESPACES"
if [ ! -f "bq/app/dependencies.yaml" ]; then
    echo "Error: dependencies.yaml not found."
    exit 1
fi

echo "/*" > "$OUTPUT_FILE"
echo "  BigQuery Dependency Tree" >> "$OUTPUT_FILE"
echo "  Generated: $(date)" >> "$OUTPUT_FILE"
echo "  -------------------------------------------" >> "$OUTPUT_FILE"
python3 scripts/build_tree.py | sed 's/^/  /' >> "$OUTPUT_FILE"
echo "*/" >> "$OUTPUT_FILE"

# Store the order in a variable to avoid multiple disk reads or Python calls
ORDER_LIST=$(get_topological_order)

echo -e "\n-- META FUNCTIONS" >> "$OUTPUT_FILE"
while IFS="|" read -r path func; do
    if [[ "$path" == *"_meta.sql" ]]; then
        append_clean_sql "$path"
    fi
done <<< "$ORDER_LIST"

echo -e "\n-- CORE FUNCTIONS (DEPENDENCY ORDER)" >> "$OUTPUT_FILE"
while IFS="|" read -r path func; do
    if [[ "$path" != *"_meta.sql" ]]; then
        append_clean_sql "$path"
    fi
done <<< "$ORDER_LIST"

echo "Install file generated: $OUTPUT_FILE (Minify: $MINIFY)"