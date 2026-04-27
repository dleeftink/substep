#!/bin/bash
# Concatenates SQL files in topological order for BigQuery installation

OUTPUT_FILE="bq/app/install.sql"
MINIFY=true  # Set to true to enable minification
mkdir -p bq/app

# Clear and initialize output file
echo "-- Generated BigQuery Install Script" > "$OUTPUT_FILE"

# Run Python script to get sorted file paths
PATHS_FILE=$(mktemp)
python3 scripts/topo_sort.py > "$PATHS_FILE"

if [ ! -s "$PATHS_FILE" ]; then
    echo "Error: Topological sort failed or returned no files."
    rm "$PATHS_FILE"
    exit 1
fi

# Function to clean, minify, and append
append_clean_sql() {
    local file_path=$1
    echo -e "\n-- Source: $file_path" >> "$OUTPUT_FILE"
    
    if [ "$MINIFY" = true ]; then
        # MINIFICATION LOGIC:
        # 1. Perl strips multi-line /* */ and single-line -- comments
        # 2. Replace all newlines/tabs with spaces
        # 3. Collapse multiple spaces into one
        # 4. Remove spaces around common SQL operators/syntax characters
        # 5. Trim trailing semicolons
        perl -0777 -pe '
            s/\/\*.*?\*\///gs; 
            s/--.*//g; 
            s/\s+/ /g; 
            s/\s*([,()=+\-*\/])\s*/$1/g;
            s/;\s*$//;
        ' "$file_path" >> "$OUTPUT_FILE"
    else
        # STANDARD CLEANUP LOGIC:
        perl -0777 -pe 's/\/\*.*?\*\///gs; s/--.*//g' "$file_path" | \
        sed -e 's/[[:space:];]*$//' >> "$OUTPUT_FILE"
    fi
    
    echo -e ";" >> "$OUTPUT_FILE"
}

echo -e "\n-- META FUNCTIONS" >> "$OUTPUT_FILE"
grep "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    append_clean_sql "$file_path"
done

echo -e "\n-- CORE FUNCTIONS (DEPENDENCY ORDER)" >> "$OUTPUT_FILE"
grep -v "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    append_clean_sql "$file_path"
done

rm "$PATHS_FILE"
echo "Install file generated: $OUTPUT_FILE (Minify: $MINIFY)"
