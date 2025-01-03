#!/bin/bash

# Function to parse the current Teleport version
get_current_version() {
    teleport version | awk '{print $2}' | cut -c 2-  # Extract version number without "v"
}

# Function to get the latest version for a specific major version from GitHub API
get_latest_version_for_major() {
    local major_version=$1
    curl -s https://api.github.com/repos/gravitational/teleport/releases \
        | jq -r '.[].tag_name' \
        | grep "^v${major_version}\." \
        | sort -V \
        | tail -1 \
        | cut -c 2-  # Extract the latest version number without "v"
}

# Function to restart Teleport and check if it's running correctly
restart_and_check_teleport() {
    if command -v sudo &> /dev/null; then
        sudo systemctl restart teleport
    else
        systemctl restart teleport
    fi
    sleep 10  # Wait for 10 seconds to allow the service to stabilize
    if command -v sudo &> /dev/null; then
        sudo systemctl is-active --quiet teleport
    else
        systemctl is-active --quiet teleport
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Teleport service failed to start. Check logs for details."
        exit 1
    fi
}

# Function to run install command with or without sudo
run_install_command() {
    local install_command="$1"
    if command -v sudo &> /dev/null; then
        eval "$install_command"
    else
        eval "${install_command/sudo /}"  # Remove sudo if it's not available
    fi
}

# Function to prompt the user for restart
prompt_restart() {
    while true; do
        read -p "Do you want to restart the Teleport service now? (yes/[no]): " choice
        choice=${choice:-yes}  # Default to "yes" if the user presses Enter
        case "$choice" in
            yes|y|Y)
                restart_and_check_teleport
                echo "Teleport service restarted successfully."
                break
                ;;
            no|n|N)
                while true; do
                    read -p "Do you want to continue installing the next version? (yes/[no]): " continue_choice
                    continue_choice=${continue_choice:-no}  # Default to "no" if the user presses Enter
                    case "$continue_choice" in
                        yes|y|Y)
                            echo "Continuing to the next version without restart."
                            return 1  # Signal to continue without restart
                            ;;
                        no|n|N)
                            echo "Aborting the installation."
                            exit 1
                            ;;
                        *)
                            echo "Please answer 'yes' or 'no'."
                            ;;
                    esac
                done
                ;;
            *)
                echo "Please answer 'yes' or 'no'."
                ;;
        esac
    done
    return 0  # Signal that restart was performed
}

# Check dependencies
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: curl and jq are required. Please install them."
    exit 1
fi

# Main script
current_version=$(get_current_version)
if [[ -z "$current_version" ]]; then
    echo "Error: Unable to determine current Teleport version."
    exit 1
fi

echo "Current Teleport version: $current_version"

while true; do
    # Extract the major version
    current_major=$(echo "$current_version" | cut -d '.' -f 1)

    # Get the latest version for the next major version
    next_major=$((current_major + 1))
    latest_next_version=$(get_latest_version_for_major "$next_major")

    if [[ -z "$latest_next_version" ]]; then
        echo "You are on the latest major version: $current_version"
        break
    fi

    echo "Upgrading from v$current_major to v$next_major"
    echo "Latest version for v$next_major: $latest_next_version"

    # Upgrade Teleport
    upgrade_command="curl https://cdn.teleport.dev/install-v${current_version}.sh | bash -s ${latest_next_version} oss"
    echo "Executing: $upgrade_command"
    run_install_command "$upgrade_command"

    # Prompt the user for a restart
    prompt_restart
    restart_status=$?

    if [[ $restart_status -eq 0 ]]; then
        # Recheck the current version after restart
        current_version=$(get_current_version)
        echo "New Teleport version: $current_version"

        if [[ "$current_version" == "$latest_next_version" ]]; then
            echo "Successfully upgraded to $current_version"
        else
            echo "Error: Upgrade failed. Please check logs."
            exit 1
        fi
    else
        echo "Skipping version check due to no restart."
    fi
done

echo "Teleport is up to date: $current_version"
