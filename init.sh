#!/bin/sh
set -e # Exit immediately if a command exits with a non-zero status

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Environment
CONFIG="/etc/access/config.env"
BIN="/usr/local/bin/access"
LIB="/usr/local/lib/access"
INSTALLED=false

YN="Please answer [Y]es or [N]o"
ABORTED="Installation aborted."

# Check if config file exists
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
fi

# Check if Access is already installed
if [ -f "$BIN" ] && [ -d "$LIB" ]; then
    INSTALLED=true
fi

# Generic input prompt function
prompt_input() {
    _prompt="$1"
    _validation_type="${2:-any}"  # any, yes_no, non_empty
    _abort_msg="$3"
    _default="$4"
    
    while true; do
        if [ -n "$_default" ]; then
            printf "%s [%s]: " "$_prompt" "$_default"
        else
            printf "%s: " "$_prompt"
        fi
        
        read -r _input
        
        # Use default if empty input provided
        [ -z "$_input" ] && [ -n "$_default" ] && _input="$_default"
        
        case "$_validation_type" in
            "yes_no")
                case "$_input" in
                    [Yy]* ) return 0 ;;
                    [Nn]* ) 
                        [ -n "$_abort_msg" ] && printf "%s\n" "$_abort_msg"
                        return 1 ;;
                    * ) printf "Please enter Y or N. " ;;
                esac
                ;;
            "non_empty")
                if [ -n "$_input" ]; then
                    PROMPT_RESULT="$_input"
                    return 0
                else
                    printf "Input cannot be empty. "
                fi
                ;;
            "any"|*)
                PROMPT_RESULT="$_input"
                return 0
                ;;
        esac
    done
}
