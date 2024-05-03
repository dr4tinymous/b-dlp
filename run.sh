run() {
    local log_dir="$LOG_DIR"
    local config_dir="$CONFIG_DIRECTORY"

    if [ -e "$log_dir" ] && ! [ -d "$log_dir" ]; then
        echo "$log_dir exists and is not a directory. Please check the configuration."
        return 1
    fi

    mkdir -p "$log_dir"

    local config_files
    mapfile -t config_files < <(find "$config_dir" -type f -printf "%f\n")
    if [ ${#config_files[@]} -eq 0 ]; then
        echo "No configurations found to select: Directory empty or not found."
        return 1
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
            echo "Parallel downloads have started. Check the logs for details."
        else
            echo "Execution cancelled."
        fi
    else
        echo "No configurations selected for execution."
    fi
}
