#!/bin/bash
EXIT_REQUIRED_COMMAND_NOT_FOUND=101
EXIT_INVALID_INPUT=102
EXIT_FILE_CREATION_FAILED=103
EXIT_USER_ABORTED=104

source config.conf || { echo "Failed to source config.conf"; exit 1; }
echo "Sourced config.conf successfully"

log() {
    local function_name=$1
    local level=$2
    local message=$3
    if [[ -z "$level" || -z "$message" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - Logging error in function $function_name: Missing level or message" >> "$LOG_FILE_PATH"
        return
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - [$function_name] - $message" >> "$LOG_FILE_PATH"
}

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

check_command() {
    local missing_commands=()
    for cmd in $COMMANDS; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log "${FUNCNAME[0]}" "ERROR" "Missing commands: ${missing_commands[*]}"
        echo "Error: The following commands are required but not installed: ${missing_commands[*]}. Please install them and rerun the script."
        exit $EXIT_REQUIRED_COMMAND_NOT_FOUND
    fi
}

get_user_input() {
  whiptail --inputbox "$1" 8 78 --title "$2" 3>&1 1>&2 2>&3
}

validate_input() {
    local input="$1"
    local pattern="$2"
    local error_message="$3"
    log "${FUNCNAME[0]}" "DEBUG" "Validating input: '$input' with pattern: '$pattern'"
    if ! [[ "$input" =~ $pattern ]]; then
        log "${FUNCNAME[0]}" "ERROR" "$error_message"
        echo "Error: $error_message"
        return $EXIT_INVALID_INPUT
    fi   
    return 0
}

launch_tmux_session() {
    if command -v tmux >/dev/null; then
        if [ -z "$TMUX" ]; then
            local session_number
            session_number=$(tmux list-sessions -F '#{session_name}' | grep -E '^yt-menu-[0-9]+$' | cut -d '-' -f 3 | sort -nr | head -n 1)
            session_number=$((session_number + 1))
            local session_name="yt-menu-${session_number}"
            tmux new-session -s "$session_name" -d
            tmux send-keys -t "$session_name" "$0" C-m
            tmux attach-session -t "$session_name"
        else
            echo "Already in a tmux session. Continuing here."
            main_menu
        fi
    else
        echo "tmux is not installed. Running script in the current terminal."
        main_menu
    fi
}

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

delete() {
  local config_dir="$CONFIG_DIRECTORY"
  local config_files
  mapfile -t config_files < <(find "$config_dir" -type f -printf "%f\n")
  if [ ${#config_files[@]} -eq 0 ]; then
    log "${FUNCNAME[0]}" "WARN" "No configurations to delete: Directory empty or not found."
    echo "No configurations found."
    return
  fi
  local checklist_options=()
  for i in "${!config_files[@]}"; do
    checklist_options+=("$i" "${config_files[$i]}" "OFF")
  done
  local selected
  selected=$(whiptail --title "Delete Configuration" --checklist "Select configurations to delete:" 15 78 ${#config_files[@]} "${checklist_options[@]}" 3>&1 1>&2 2>&3)
  IFS=' ' read -r -a selected <<< "${selected//\"/}"
  if [ ${#selected[@]} -gt 0 ]; then
    if whiptail --title "Confirm Delete" --yesno "Are you sure?" 10 60; then
      for config_index in "${selected[@]}"; do
        rm -f "$config_dir/${config_files[$config_index]}"
        log "${FUNCNAME[0]}" "INFO" "Deleted configuration file: '${config_files[$config_index]}'."
        echo "Deleted: '${config_files[$config_index]}'."
      done
    else
      log "${FUNCNAME[0]}" "INFO" "Deletion cancelled by user."
      echo "Deletion cancelled."
    fi
  else
    log "${FUNCNAME[0]}" "INFO" "No configuration selected for deletion by user."
    echo "No configuration selected."
  fi
}

run() {
    local config_dir="$CONFIG_DIRECTORY"
    local log_dir="$LOG_FILE_PATH"
    mkdir -p "$log_dir"
    local config_files
    mapfile -t config_files < <(find "$config_dir" -type f -printf "%f\n")
    if [ ${#config_files[@]} -eq 0 ]; then
        log "${FUNCNAME[0]}" "WARN" "No configurations found to select: Directory empty or not found."
        echo "No configurations found."
        return
    fi
    local checklist_options=()
    for i in "${!config_files[@]}"; do
        checklist_options+=("$i" "${config_files[$i]}" "OFF")
    done
    local selected
    selected=$(whiptail --title "Select Configurations" --checklist "Choose configurations to run:" 20 78 ${#config_files[@]} "${checklist_options[@]}" 3>&1 1>&2 2>&3)
    IFS=' ' read -r -a selected <<< "${selected//\"/}"
    if [ ${#selected[@]} -gt 0 ]; then
        if whiptail --title "Confirm Execution" --yesno "Run the selected configurations?" 10 60; then
            for config_index in "${selected[@]}"; do
                local config_file="${config_dir}/${config_files[$config_index]}"
                local command="yt-dlp --config-location '$config_file' >> '$log_dir/${config_files[$config_index]}_log.txt' 2>&1"
                local start_msg
				start_msg="echo \"$(date '+%Y-%m-%d %H:%M:%S') - INFO: Starting yt-dlp for $config_file\" > '$log_dir/${config_files[$config_index]}_log.txt'"
                local end_msg
				end_msg="if [ $? -eq 0 ]; then echo \"$(date '+%Y-%m-%d %H:%M:%S') - INFO: Successfully completed download for $config_file\" >> '$log_dir/${config_files[$config_index]}_log.txt'; else echo \"$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Download failed for $config_file\" >> '$log_dir/${config_files[$config_index]}_log.txt'; fi"
                eval "$start_msg && $command && $end_msg"
            done
            log "${FUNCNAME[0]}" "INFO" "All configurations have completed. Check the logs for details."
            echo "Parallel downloads have started. Check the logs for details."
        else
            log "${FUNCNAME[0]}" "INFO" "Execution cancelled by user."
            echo "Execution cancelled."
        fi
    else
        log "${FUNCNAME[0]}" "INFO" "No configurations selected for execution by user."
        echo "No configurations selected."
    fi
}

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

declare -A menu_actions=(
    [1]=create
    [2]=run
    [3]=delete
    [4]=ad_hoc_run
    [5]="exit_script"
)

exit_script() {
    echo "Exiting..."
    exit 0
}

main_menu() {
    while true; do
        choice=$(whiptail --title "Configuration Menu" --menu "Choose an option" 15 60 5 \
            "1" "Create" \
            "2" "Select" \
            "3" "Delete" \
            "4" "Ad-Hoc" \
            "5" "Exit" 3>&2 2>&1 1>&3)
        if [[ -n "${menu_actions[$choice]}" ]]; then
            ${menu_actions[$choice]}
        else
            echo "Invalid option."
        fi
    done
}

trap 'handle_exit' SIGINT

handle_exit() {
  log "${FUNCNAME[0]}" "INFO" "Script interrupted by user. Rotating logs before exiting."
  echo "Script interrupted. Exiting..."
  rotate_logs
  exit $EXIT_USER_ABORTED
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    launch_tmux_session
fi
