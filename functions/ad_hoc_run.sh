ad_hoc_run() {
    log "${FUNCNAME[0]}" "DEBUG" "Starting ad-hoc command setup."
    local url_or_query
    url_or_query=$(get_user_input "Enter URL or search query:" "URL or Search Query")
    if [[ -z "$url_or_query" ]]; then
        log "${FUNCNAME[0]}" "WARN" "Ad-hoc execution cancelled by user due to no URL/query input."
        echo "Ad-hoc execution cancelled."
        return $EXIT_USER_ABORTED
    fi
    local safe_input
    if [[ "$url_or_query" =~ ^https?:// ]]; then
        safe_input=$(printf '%q' "$url_or_query")
    elif [[ "$url_or_query" =~ ^[a-zA-Z0-9_+\ -]+$ ]]; then
        safe_input="ytsearch:$(printf '%q' "$url_or_query")"
    else
        log "${FUNCNAME[0]}" "ERROR" "Invalid URL or query: $url_or_query contains invalid characters."
        echo "Error: URL or query contains invalid characters."
        return $EXIT_INVALID_INPUT
    fi
    local max_files
    max_files=$(get_user_input "Maximum number of files to download (0 for unlimited):" "Maximum Downloads")
    if ! [[ "$max_files" =~ ^[0-9]+$ ]]; then
        log "${FUNCNAME[0]}" "ERROR" "Invalid number format for max files: $max_files must be a positive integer."
        echo "Error: Maximum number of files must be a positive integer."
        return $EXIT_INVALID_INPUT
    fi
    local download_limit
    download_limit=$( [ "$max_files" -eq 0 ] && echo "--playlist-end 99999" || echo "--playlist-end $max_files" )
    local duration_input
    duration_input=$(get_user_input "Min & max duration in seconds (optional, format min-max):" "Duration Filter")
    local match_filter=""
    if [[ "$duration_input" =~ ^[0-9]+-[0-9]+$ ]]; then
        match_filter="--match-filter \"duration >= ${duration_input%-*} & duration <= ${duration_input#*-}\""
    fi
    local final_command
    final_command="yt-dlp $safe_input $download_limit --output '$OUTPUT_FORMAT' --download-archive '$ARCHIVE_FILE_PATH' --extract-audio --audio-format '$AUDIO_FORMAT' --audio-quality $AUDIO_QUALITY $match_filter --no-overwrite --concurrent-fragments $CONCURRENT_FRAGMENTS --postprocessor-args \"-threads $THREADS_PER_POSTPROCESSOR\""
    echo "Final command to execute: $final_command"
    log "${FUNCNAME[0]}" "INFO" "Executing ad-hoc command: $final_command"
    eval "$final_command"
    log "${FUNCNAME[0]}" "INFO" "Ad-hoc command executed successfully."
}
