# Function to log messages with a timestamp
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

# Function to check if necessary commands are available
check_command() {
    local missing_commands=()
    for cmd in "${COMMANDS[@]}"; do
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

# Function to launch a new tmux session or attach to an existing one
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

# Function to get user input with a GUI dialog
get_user_input() {
    whiptail --inputbox "$1" 8 78 --title "$2" 3>&1 1>&2 2>&3
}

# Function to validate input against a regex pattern
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
