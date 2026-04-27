#!/bin/bash
# Concatenates SQL files in topological order for BigQuery installation

OUTPUT_FILE="bq/app/install.sql"
mkdir -p bq/app

# Clear and initialize output file
echo "-- Generated BigQuery Install Script" > "$OUTPUT_FILE"

# Run Python script to get sorted file paths
PATHS_FILE=$(mktemp)
python3 scripts/topo_sort.py > "$PATHS_FILE"

# Check if Python output is empty or failed
if [ ! -s "$PATHS_FILE" ]; then
    echo "Error: Topological sort failed or returned no files."
    rm "$PATHS_FILE"
    exit 1
fi

# Function to strip comments and append
append_clean_sql() {
    local file_path=$1
    echo -e "\n-- Source: $file_path" >> "$OUTPUT_FILE"
    
    # 1. Perl strips multi-line /* */ and single-line -- comments
    # 2. We then trim trailing whitespace/semicolons and add exactly ONE semicolon
    perl -0777 -pe 's/\/\*.*?\*\///gs; s/--.*//g' "$file_path" | \
    sed -e 's/[[:space:];]*$//' >> "$OUTPUT_FILE"
    
    echo -e ";" >> "$OUTPUT_FILE"
}

# 1. Process Meta functions first
echo -e "\n-- ==========================================" >> "$OUTPUT_FILE"
echo "-- META FUNCTIONS" >> "$OUTPUT_FILE"
echo "-- ==========================================" >> "$OUTPUT_FILE"

grep "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    append_clean_sql "$file_path"
done

# 2. Process Core functions
echo -e "\n-- ==========================================" >> "$OUTPUT_FILE"
echo "-- CORE FUNCTIONS (DEPENDENCY ORDER)" >> "$OUTPUT_FILE"
echo -e "-- ==========================================\n" >> "$OUTPUT_FILE"

grep -v "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    append_clean_sql "$file_path"
done

# Cleanup
rm "$PATHS_FILE"

echo "Install file generated: $OUTPUT_FILE"
