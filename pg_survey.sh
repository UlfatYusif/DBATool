#!/bin/bash

# =======================================================
# PostgreSQL DBA Morning Survey
# Version 0.1
# The script created for Survey
# This will be run from the crontab
# It will list top dead tuples
# Also it will collect huge tables
# Table size and Dead Tuple threshold configurable
# The script also will compare result with previouse day
# =======================================================

CONFIG_FILE="./config.txt"

# ---- Load config ----
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Config file not found!"
        exit 1
    fi
    source "$CONFIG_FILE"
}

# ---- Prepare environment ----
init() {
    mkdir -p "$LOG_DIR"
    TODAY=$(date +%F)
    YESTERDAY=$(date -d "yesterday" +%F 2>/dev/null || date -v -1d +%F)

    OUTPUT_FILE="$LOG_DIR/${OUTPUT_PREFIX}_${TODAY}.log"
    PREV_FILE="$LOG_DIR/${OUTPUT_PREFIX}_${YESTERDAY}.log"
}

# ---- Get Dead Tuples ----
get_dead_tuples() {
    echo "==== Dead Tuples (Threshold: $DEAD_TUPLE_THRESHOLD) ====" >> "$OUTPUT_FILE"

    psql -At <<EOF >> "$OUTPUT_FILE"
SELECT schemaname||'.'||relname,
       n_dead_tup
FROM pg_stat_user_tables
WHERE n_dead_tup > $DEAD_TUPLE_THRESHOLD
ORDER BY n_dead_tup DESC;
EOF

    echo "" >> "$OUTPUT_FILE"
}

# ---- Get Large Tables ----
get_large_tables() {
    echo "==== Large Tables (Threshold: ${TABLE_SIZE_THRESHOLD_MB} MB) ====" >> "$OUTPUT_FILE"

    psql -At <<EOF >> "$OUTPUT_FILE"
SELECT schemaname||'.'||relname,
       pg_total_relation_size(relid)/1024/1024 AS size_mb
FROM pg_catalog.pg_statio_user_tables
WHERE pg_total_relation_size(relid)/1024/1024 > $TABLE_SIZE_THRESHOLD_MB
ORDER BY size_mb DESC;
EOF

    echo "" >> "$OUTPUT_FILE"
}

# ---- Compare Results ----
compare_results() {
    if [[ "$ENABLE_COMPARE" != "true" ]]; then
        return
    fi

    if [[ ! -f "$PREV_FILE" ]]; then
        echo "No previous file to compare." >> "$OUTPUT_FILE"
        return
    fi

    echo "==== Comparison with Yesterday ====" >> "$OUTPUT_FILE"

    # Extract sections
    grep -A1000 "Dead Tuples" "$OUTPUT_FILE" | tail -n +2 > /tmp/today_dead.txt
    grep -A1000 "Dead Tuples" "$PREV_FILE" | tail -n +2 > /tmp/yest_dead.txt

    grep -A1000 "Large Tables" "$OUTPUT_FILE" | tail -n +2 > /tmp/today_size.txt
    grep -A1000 "Large Tables" "$PREV_FILE" | tail -n +2 > /tmp/yest_size.txt

    echo "--- Dead Tuple Changes ---" >> "$OUTPUT_FILE"
    join_compare /tmp/yest_dead.txt /tmp/today_dead.txt >> "$OUTPUT_FILE"

    echo "--- Table Size Changes ---" >> "$OUTPUT_FILE"
    join_compare /tmp/yest_size.txt /tmp/today_size.txt >> "$OUTPUT_FILE"

    echo "" >> "$OUTPUT_FILE"
}

# ---- Generic comparison function ----
join_compare() {
    sort "$1" > /tmp/a.txt
    sort "$2" > /tmp/b.txt

    join -t'|' -a1 -a2 -e "0" -o 0,1.2,2.2 /tmp/a.txt /tmp/b.txt | while IFS='|' read table old new
    do
        diff=$((new - old))
        pct=0

        if [[ "$old" -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.2f\", ($diff/$old)*100}")
        fi

        echo "$table | yesterday=$old | today=$new | change=$diff | ${pct}%"
    done
}

# ---- Main ----
main() {
    load_config
    init

    echo "PostgreSQL Morning Survey - $TODAY" > "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    get_dead_tuples
    get_large_tables
    compare_results

    echo "Report generated: $OUTPUT_FILE"
}

main
