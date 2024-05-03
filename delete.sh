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
