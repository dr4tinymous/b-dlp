#!/bin/bash
EXIT_REQUIRED_COMMAND_NOT_FOUND=101
EXIT_INVALID_INPUT=102
EXIT_FILE_CREATION_FAILED=103
EXIT_USER_ABORTED=104

source ./functions/create.sh
source ./functions/delete.sh
source ./functions/utils.sh
source ./functions/rotate_logs.sh
source ./functions/ad_hoc_run.sh
source ./functions/run.sh
source config.conf || { echo "Failed to source config.conf"; exit 1; }
echo "Sourced config.conf successfully"

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
        choice=$(whiptail --title "Main Menu" --menu "" 25 100 5 \
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
