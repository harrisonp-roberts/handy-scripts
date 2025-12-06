#!/bin/bash
###############################################################################
# Utility to check the status of backups created with the restic-backup service
#
# TODO: clean up various error outputs

# Constants

HOME_DIR=$(eval echo "~${USER}")
CONFIG_DIR="${HOME_DIR}"/.config
CONFIG_FILE="${CONFIG_DIR}/bk.config"
PIDFILE="${HOME_DIR}/.cache/restic.pid"

# Global Variables
VERBOSE=false
COMMAND=""

usage() {
    printf "bk is a utility to manage backups created using the restic backup"
    printf "service.\n"
    printf "capabilities:\n"
    printf "    open and close a backup repository\n"
    printf "examples:\n"
    printf "    - bk open\n"
    printf "    - bk install\n"
    printf "    - bk uninstall\n"
    exit 0
}

debug() {
    local -r msg="$1"

    if [ $VERBOSE = true ]; then
        printf "DEBUG: %s\n" "${msg}"
    fi
}

set_command() {
    local -r command=${1}

    if [ -z "${COMMAND}" ]; then
        COMMAND="${command}"
    else
        printf "Error: Only a single command can be used at a time\n"
        exit 1
    fi
}

set_config() {
    local -r property_key="$1"
    local -r property_value="$2"
    local -r entry="${property_key}=${property_value}"

    local -r property_line_number=$(grep -n "${property_key}" | head -1 | cut -d: -f1)
    if [ -z "${property_line_number}" ]; then 
        # the property does not already exist, append it to the file
        echo "${entry}" >> "${CONFIG_FILE}"
    else 
        sed -i "Ns/.*/${entry}/" "${CONFIG_FILE}"
    fi
}

read_config() {
    local -r property_name="$1"
    local property

    property=$(cat "${CONFIG_FILE}" | grep "${property_name}=" | cut -d'=' -f2-)
    if [ ! -z "${property}" ]; then
        echo "${property}"
    fi
}

# unmounts restic repository
remove_restic_remote() {
    local mount_point=$1

    if [ ! -d "${mount_point}" ]; then
        printf "%s is not a directory!" "${mount_point}"
        exit 1
    fi

    sudo umount "${mount_point}"
}

# Mounts the restic backup repository's directory using rclone
mount_rclone_remote() {
    local rclone_remote_name=$1
    local mount_point=$2

    if [ -z "${rclone_remote_name}" ] || [ -z "${mount_point}" ]; then
        printf "remote name and mount point are required to mount a remote repository\n"
        exit 1
    fi

    rclone about "${rclone_remote_name}" >/dev/null

    if [ $? -ne 0 ]; then
        printf "rclone remote '%s' not found\n" "${rclone_remote_name}"
        exit 1
    fi

    if [ ! -d "${mount_point}" ]; then
        printf "rclone mount directory %s not found\n" "'${rclone_remote_name}'"
        exit 1
    fi

    if [ ! -z "$(ls -A "${mount_point}")" ]; then
        printf "rclone mount directory %s is not empty\n" "'${mount_point}'"
        exit 1
    fi

    rclone mount "${rclone_remote_name}" "${mount_point}" --daemon
    return $?
}

unmount_rclone_remote() {
    local mount_point=$1

    if [ ! -d "${mount_point}" ]; then
        printf "mount point %s is not a valid directory\n" "'${mount_point}'"
        exit 1
    fi

    mountpoint -q "${mount_point}"
    if [ $? -ne 0 ]; then
        printf "mount point %s is not a mount point\n" "${mount_point}"
        exit 1
    fi

    sudo umount "${mount_point}"
}

mount_restic_repository() {
    local -r repository_path=$1
    local -r mount_directory=$2
    local -r repository_password=$3
    local restic_pid=""

    mountpoint -q "${mount_directory}" || {

        if [ "$(find "${mount_directory}" -maxdepth 1 | wc -l)" -gt 0 ]; then
            printf "'%s' is not empty\n" "${mount_directory}" 1>&2
            return 1
        fi

        echo "${repository_password}" | restic -r "${repository_path}" mount "${mount_directory}" >/dev/null 2>&1 &
        restic_pid=$!

        echo "${restic_pid}" >"${PIDFILE}"
        sleep 15
    }

    if mountpoint -q "${mount_directory}"; then
        return 0
    else
        kill "${restic_pid}"
        return 1
    fi
}

close_restic_repository() {
    printf "closing restic repository...\n"
}

cleanup() {
    printf "cleaning up\n"
    unmount_rclone_remote "${rclone_mount_directory}"
}

create_secret() {
    local -r secret="$1"
    local -r credential_directory="$2"
    local -r credential_name="$3"

    if [ ! -d "${credential_directory}" ]; then
        printf "directory '%s' does not exist" "${credential_filepath}" >&2
        return 1
    fi

    echo "${secret}" | systemd-creds encrypt --with-key=tpm2 --name="${credential_name}" - "${credential_directory}/${credential_name}"
}

read_secret() {
    local -r credential_filepath="$1"

    if [ ! -f "${credential_filepath}" ]; then
        printf "credential file '%s' does not exist\n" "${credential_filepath}" >&2
        return 1
    fi

    local -r decrypted_secret=$(systemd-creds decrypt "${credential_filepath}" 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "${decrypted_secret}"
    else
        printf "failed to read secret at '%s'" "${credential_filepath}"
    fi
}

uninstall() {
    local -r HOME_DIR=$(eval echo "~${USER}")
    local -r install_path="${HOME_DIR}/.local/bin/bk"

    # script assumes systemd compatibility and presence of ~/.local/bin
    if [ ! -z "${install_path}" ]; then
        printf "removing existing installation\n"
        rm -f "${install_path}"
        rm -f "${CONFIG_FILE}"
    fi
}

handle_open_command() {
    local -r restic_mount_directory=$(read_config "RESTIC_MOUNT")
    local -r rclone_mount_directory=$(read_config "RCLONE_MOUNT")
    local -r rclone_remote_name=$(read_config "RCLONE_REMOTE_NAME")

    local -r repository_password=$(read_secret "${CONFIG_DIR}/repository_password.cred")
    local -r repository_id=$(read_secret "${CONFIG_DIR}/repository_id.cred")

    if [ -z "${restic_mount_directory}" ]; then
        printf " -- %s" '-m backup mount directory parameter is required'
        exit 1
    fi

    if [ -z "${repository_password}" ]; then
        printf " -- %s" "-p restic repository password parameter is required\n"
        exit 1
    fi

    printf "mounting remote storage to %s...\n" "${rclone_mount_directory}"
    mount_rclone_remote "${rclone_remote_name}" "${rclone_mount_directory}" || {
        printf "mounting failed. exiting\n"
        cleanup
        exit 1
    }

    printf "remote storage mounted\n"
    printf "opening repository at '%s'...\n" "${restic_mount_directory}"
    # use restic to open repository mounted at rclone_mount directory
    mount_restic_repository "${rclone_mount_directory}" "${restic_mount_directory}" "${repository_password}" || {
        printf "could not mount restic repository. exiting\n"
        cleanup
        exit 1
    }

    local -r restic_pid=$(cat "${PIDFILE}")
    printf "repository opened at '%s'\n" "${restic_mount_directory}"
    printf "go to '%s' to browse recent snapshots\n\n" "${restic_mount_directory}"
    printf "to close the repository run bk close, or kill the restic process '%s' and unmount '%s'" "${restic_pid}" "${rclone_mount_directory}"
}

handle_close_command() {
    local -r rclone_mount_directory=$(read_config "RCLONE_MOUNT")

    printf "closing repository\n"
    restic_pid=$(cat "${PIDFILE}")
    if [ -z "${restic_pid}" ]; then
        printf "%s is required!\n" "${restic_pid}"
        exit 1
    fi

    kill "${restic_pid}"
    truncate -s0 "${PIDFILE}"
    sleep 5
    unmount_rclone_remote "${rclone_mount_directory}"
}

install() {
    local -r install_path="${HOME_DIR}/.local/bin/bk"
    local -r config_path="${CONFIG_DIR}/bk"

    if [ ! -d "${HOME_DIR}/.local/bin" ]; then
        printf "%s/.local/bin directory is required for installation" "${HOME_DIR}"
        exit 1
    fi

    local keep_config="n"

    if [ -f "${install_path}" ]; then
        read -r -p "would you like to keep your current config? (y/n)" "keep_config"
    fi

    if [ "${keep_config}" != "y" ]; then
        printf "please enter your restic repository ID and password\n"
        read -r -p "restic repository ID: " repository_id
        read -r -p "what is the repository password: " repository_password
        printf "\n"

        printf "please enter the directory that rclone will mount the repository files to, and the directory that restic will mount the opened backup to\n"
        read -r -p "what is the rclone mount directory: " rclone_mount
        read -r -p "what is the restic mount directory: " restic_mount
        read -r -p "what is the name of your (already configured) rclone remote:" rclone_remote_name
        printf "removing previous configuration and installation...\n"
        uninstall
        printf "previous configuration and installation removed\n"

        printf "setting config file '%s'" "${CONFIG_FILE}"

        {
            echo "RCLONE_MOUNT=" "${rclone_mount}"
            echo "RESTIC_MOUNT=${restic_mount}"
            echo "RCLONE_REMOTE_NAME=${rclone_remote_name}"
        } >>"${CONFIG_FILE}"

        printf "updated config file %s!\n" "${CONFIG_FILE}"
        cat "${CONFIG_FILE}"
        create_secret "${repository_password}" "${CONFIG_DIR}" "repository_password.cred"
        create_secret "${repository_id}" "${CONFIG_DIR}" "repository_id.cred"
    else
        printf "keeping previous configuration\n"
        printf "removing previous installation...\n"
        rm -f "${install_path}"
        printf "previous installation removed\n"
    fi

    printf "installing bk\n"
    cp "./bk.sh" "${install_path}"
    printf "bk installed!\n"
    exit 0
}

main() {
    case $COMMAND in
        open) handle_open_command ;;
        close) handle_close_command ;;
        install) handle_install_command ;;
        uninstall) handle_uninstall_command ;;
        *) usage ;;
    esac
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help) usage exit 0 ;;
    -pid | --restic-pid) restic_pid=$2 shift ;;
    -v | --verbose) VERBOSE=true ;;
    open) set_command "open" ;;
    close) set_command "close" ;;
    install) set_command "install" ;;
    uninstall) set_command "uninstall" ;;
    *) usage ;;
    esac
    shift
done

main
