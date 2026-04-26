#!/bin/bash
# Install script for substep BigQuery functions
# Concatenates SQL files in topological dependency order

OUTPUT_FILE="bq/install.sql"
ORDER_FILE="bq/install-order.txt"

# Generate topological order (excluding meta functions, as they go first)
python3 scripts/topo_sort.py | grep -v '\.meta$' > "$ORDER_FILE"

# Add meta functions first
echo "# Meta functions (no dependencies)" > "$OUTPUT_FILE"
for meta in def.meta lay.meta fix.meta cue.meta map.meta try.meta use.meta get.meta; do
  FILE_PATH=$(find bq -name "_meta.sql" -path "*/${meta%.*}/*" | head -1)
  if [ -f "$FILE_PATH" ]; then
    echo "-- $meta" >> "$OUTPUT_FILE"
    cat "$FILE_PATH" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  fi
done

# Add remaining functions in topological order
echo "# Core functions (in dependency order)" >> "$OUTPUT_FILE"
while IFS= read -r func; do
  # Map function name to file path (e.g., get.safeJson -> bq/get/safeJson.sql)
  namespace=${func%%.*}
  name=${func#*.}
  FILE_PATH="bq/$namespace/$name.sql"
  if [ -f "$FILE_PATH" ]; then
    echo "-- $func" >> "$OUTPUT_FILE"
    cat "$FILE_PATH" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  fi
done < "$ORDER_FILE"

echo "Install file generated: $OUTPUT_FILE"
echo "To install in BigQuery: bq query --use_legacy_sql=false < $OUTPUT_FILE"