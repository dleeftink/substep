#!/bin/bash
# Concatenates SQL files in topological order for BigQuery installation

OUTPUT_FILE="bq/app/install.sql"
mkdir -p bq/app

# Clear and initialize output file
echo "-- Generated BigQuery Install Script" > "$OUTPUT_FILE"

# Run Python script to get sorted file paths
# Stores results in a temporary file
PATHS_FILE=$(mktemp)
python3 scripts/topo_sort.py > "$PATHS_FILE"

# Check if Python output is empty or failed
if [ ! -s "$PATHS_FILE" ]; then
    echo "Error: Topological sort failed or returned no files."
    rm "$PATHS_FILE"
    exit 1
fi

# 1. Process Meta functions first (priority)
echo -e "\n-- ==========================================" >> "$OUTPUT_FILE"
echo "-- META FUNCTIONS" >> "$OUTPUT_FILE"
echo "-- ==========================================" >> "$OUTPUT_FILE"

grep "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    echo -e "\n-- Source: $file_path" >> "$OUTPUT_FILE"
    cat "$file_path" >> "$OUTPUT_FILE"
    echo -e "" >> "$OUTPUT_FILE"
done

# 2. Process Core functions (everything else)
echo -e "\n-- ==========================================" >> "$OUTPUT_FILE"
echo "-- CORE FUNCTIONS (DEPENDENCY ORDER)" >> "$OUTPUT_FILE"
echo -e "-- ==========================================\n" >> "$OUTPUT_FILE"

grep -v "_meta.sql" "$PATHS_FILE" | while read -r file_path; do
    echo "-- Source: $file_path" >> "$OUTPUT_FILE"
    cat "$file_path" >> "$OUTPUT_FILE"
    echo -e "\n" >> "$OUTPUT_FILE"
done

# Cleanup
rm "$PATHS_FILE"

echo "Install file generated: $OUTPUT_FILE"
echo "To install: bq query --use_legacy_sql=false < $OUTPUT_FILE"
