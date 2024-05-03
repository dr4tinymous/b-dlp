create() {
    log "${FUNCNAME[0]}" "DEBUG" "Checking for required commands: $COMMANDS"
    log "${FUNCNAME[0]}" "INFO" "Creating necessary directories: $CONFIG_DIRECTORY, $DOWNLOAD_DIRECTORY"
    if ! mkdir -p "$CONFIG_DIRECTORY" "$DOWNLOAD_DIRECTORY"; then
        log "${FUNCNAME[0]}" "ERROR" "Failed to create directories: $CONFIG_DIRECTORY or $DOWNLOAD_DIRECTORY"
        echo "Error: Failed to create necessary directories."
        return $EXIT_FILE_CREATION_FAILED
    fi
    local config_name
    config_name=$(get_user_input "Configuration name:" "Configuration Name")
    if ! validate_input "$config_name" '^[a-zA-Z0-9_-]+$' "Invalid configuration name: $config_name contains invalid characters."; then
        return $EXIT_INVALID_INPUT
    fi
    local url_or_query
    url_or_query=$(get_user_input "URL or query:" "URL or Query")
    if ! validate_input "$url_or_query" "$URL_OR_QUERY_PATTERN" "Invalid URL or query: $url_or_query contains invalid characters."; then
        return $EXIT_INVALID_INPUT
    fi
    local safe_input
    if [[ "$url_or_query" =~ ^https?:// ]]; then
        safe_input=$(printf '%q' "$url_or_query")
    else
        safe_input="ytsearch:$(printf '%q' "$url_or_query")"
    fi
    local config_file="$CONFIG_DIRECTORY/$config_name"
    if [[ -f "$config_file" ]]; then
        if ! whiptail --title "File exists" --yesno "Configuration file already exists. Overwrite?" 10 60; then
            log "${FUNCNAME[0]}" "WARN" "Configuration creation cancelled, file exists and overwrite not confirmed."
            echo "Configuration creation cancelled."
            return $EXIT_USER_ABORTED
        fi
    fi
    local max_files
    max_files=$(get_user_input "Maximum number of files to download (0 for unlimited):" "Maximum Downloads")
    if ! [[ "$max_files" =~ ^[0-9]+$ ]]; then
        log "${FUNCNAME[0]}" "ERROR" "Invalid number format for max files: $max_files must be a positive integer."
        echo "Error: Maximum number of files must be a positive integer."
        return $EXIT_INVALID_INPUT
    fi
    local download_limit
    download_limit=$([ "$max_files" -eq 0 ] && echo "--playlist-end 99999" || echo "--playlist-end $max_files")
    local duration_input
    duration_input=$(get_user_input "Min & max duration in seconds (optional, format min-max):" "Duration Filter")
    local match_filter=""
    if [[ "$duration_input" =~ ^[0-9]+-[0-9]+$ ]]; then
        match_filter="--match-filter \"duration >= ${duration_input%-*} & duration <= ${duration_input#*-}\""
    fi
    local upload_date
    upload_date=$(get_user_input "Maximum upload age in YYYYMMDD format (optional):" "Upload Date")
    local dateafter=""
    if [[ "$upload_date" =~ ^[0-9]{8}$ ]]; then
        dateafter="--dateafter $upload_date"
    else
        log "${FUNCNAME[0]}" "WARN" "Invalid date format but proceeding without date filter: $upload_date"
        echo "Warning: Invalid date format. Proceeding without date filter."
    fi
    local final_command
    final_command="$safe_input $download_limit --output '$OUTPUT_FORMAT' --download-archive '$ARCHIVE_FILE_PATH' --extract-audio --audio-format '$AUDIO_FORMAT' --audio-quality $AUDIO_QUALITY --no-overwrite $match_filter $dateafter --concurrent-fragments $CONCURRENT_FRAGMENTS --postprocessor-args \"-threads $THREADS_PER_POSTPROCESSOR\""
    if ! echo "$final_command" > "$config_file"; then
        log "${FUNCNAME[0]}" "ERROR" "Failed to write configuration to file: $config_file"
        echo "Error: Could not write configuration."
        return $EXIT_FILE_CREATION_FAILED
    fi
    log "${FUNCNAME[0]}" "INFO" "Configuration '$config_name' created successfully in $CONFIG_DIRECTORY."
    echo "Configuration '$config_name' created in $CONFIG_DIRECTORY."
}
