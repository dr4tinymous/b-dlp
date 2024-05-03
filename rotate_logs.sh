rotate_logs() {
    local log_file="$LOG_FILE_PATH"
    local max_size_kb="$MAX_SIZE_KB"
    local max_files="$MAX_FILES"
    local current_size_kb
	current_size_kb=$(du -k "$log_file" | cut -f1)
    if [[ ! -f "$log_file" ]]; then
        log "${FUNCNAME[0]}" "ERROR" "Log file does not exist: $log_file"
        return
    fi
    if [[ "$current_size_kb" -lt $max_size_kb ]]; then
        log "${FUNCNAME[0]}" "DEBUG" "No need to rotate log file, size ($current_size_kb KB) is below the threshold ($max_size_kb KB)."
        return
    fi
    for ((i=max_files-1; i>0; i--)); do
        local old_file="${log_file}.${i}"
        local new_file="${log_file}.$((i+1))"
        if [[ -f "$old_file.gz" ]]; then
            if ! mv "$old_file.gz" "$new_file.gz"; then
                log "${FUNCNAME[0]}" "ERROR" "Failed to rotate log file from $old_file.gz to $new_file.gz"
            fi
        fi
    done
    if ! mv "$log_file" "${log_file}.1"; then
        log "${FUNCNAME[0]}" "ERROR" "Failed to move log file for compression: ${log_file}"
        return
    fi
    if ! gzip "${log_file}.1"; then
        log "${FUNCNAME[0]}" "ERROR" "Failed to compress log file: ${log_file}.1"
        return
    fi
    if ! touch "$log_file"; then
        log "${FUNCNAME[0]}" "ERROR" "Failed to create a new log file: $log_file"
        return
    fi
    log "${FUNCNAME[0]}" "INFO" "Log file rotated and compressed successfully."
}
