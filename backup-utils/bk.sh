#!/bin/bash
###############################################################################
# Utility to check the status of backups created with the restic-backup service
#
# TODO: clean up various error outputs

# Constants
HOME_DIR=$(eval echo "~${USER}")
CONFIG_DIR="${HOME_DIR}"/.config/bk
CONFIG_FILE="${CONFIG_DIR}/bk-config.json"
PIDFILE="${HOME_DIR}/.cache/restic.pid"

# Global Variables
use_verbose=false
command=""
repository_name=""

usage() {
    printf "bk is a utility to manage backups created using the restic backup"
    printf "service.\n"
    printf "capabilities:\n"
    printf "    save multiple backup repositories and their credentials\n"
    printf "    open a backup repository"
    printf "examples:\n"
    printf "    - bk -r repo_name open\n"
    printf "    - bk add\n"
    printf "    - bk install\n"
    printf "    - bk uninstall\n"
    exit 0
}

debug() {
    local -r msg="$1"

    if [ $use_verbose = true ]; then
        printf "DEBUG: %s\n" "${msg}"
    fi
}

set_command() {
    local -r cmd=${1}

    if [ -z "${command}" ]; then
        command="${cmd}"
    else
        printf "Error: Only a single command can be used at a time\n"
        exit 1
    fi
}

# create or update properties within a JSON configuration file
#
# mandatory parameters
#   1. the path of the key that will be created or updated in the format of "path.to.key"
#   2. the value to set
#   3. (optional) the path to the configuration file to update
set_config() {
    local -r key_path="$1"
    local -r value="$2"
    local -r config_file="${CONFIG_FILE:-$3}"
    
    local -r temp_config_file="${config_file}.tmp"

    if [ -z "${config_file}" ]; then
        printf "the config file must be specified with the CONFIG_FILE variable or by passing it as a parameter"
        exit 1
    fi

    if [ ! -f "${CONFIG_FILE}" ]; then
        debug "config file does not exist, creating config file"
        echo "{}" >> "${CONFIG_FILE}"
    fi

    debug "setting ${key_path} to ${value}"

    # we need to use the weird < < () to get the readarray input to avoid an extra empty list item for some reason
    readarray -t -d . key_array < <(printf "%s" "${key_path}")

    # we must convert the array to a json string to pass as input to jq
    local -r key_array_string=$(printf '%s\n' "${key_array[@]}" | jq -R . | jq -s .)

    # then write the value to a temp config file, then replace the old one
    cat "${config_file}" | jq --argjson path "${key_array_string}" --arg value "$value" 'setpath($path; $value)' > "${temp_config_file}"

    cat "${config_file}" | jq >> /dev/null

    if cat "${config_file}" | jq '.' >> /dev/null -ne 0; then
        # attempting to parse the temporary config file failed, so it is not valid. cleanup and exit
        printf "failed to set config value %s" "${value}"
        rm "${temp_config_file}"
        return 1
    fi 

    mv "${temp_config_file}" "${config_file}"

    return 0
}

# retrieve a property from a JSON configuration file
#
# mandatory parameters
#   1. the path of the key that will be created or updated in the format of "path.to.key"
#   2. (optional) the path to the configuration file to retrieve the value from
get_config() {
    local -r key_path="$1"
    local -r config_file="${CONFIG_FILE:-$3}"

    if [ ! -f "${config_file}" ]; then
        printf "config file %s not found\n" "${config_file}" 
    fi

    local -r value=$(jq -r ".${key_path}" "${config_file}")
    if [ "${value}" != "null" ]; then
        echo "${value}"
        return 0
    else
        echo ""
        return 1
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

        if [ "$(find "${mount_directory}" -maxdepth 1 | wc -l)" -gt 1 ]; then
            printf "'%s' is not empty\n" "${mount_directory}" 1>&2
            return 1
        fi

        echo "${repository_password}" | restic -r "${repository_path}" mount "${mount_directory}" >/dev/null 2>&1 &
        restic_pid=$!

        echo "${restic_pid}" >"${PIDFILE}"
        sleep 15
    }

    echo "mount directory: ${mount_directory}"
    mountpoint "${mount_directory}"

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
    local -r install_path="${HOME_DIR}/.local/bin/bk"

    # script assumes systemd compatibility and presence of ~/.local/bin
    if [ ! -z "${install_path}" ]; then
        rm -f "${install_path}"
        rm -rf "${CONFIG_DIR}"
    fi
}

install() {
    local -r install_path="${HOME_DIR}/.local/bin/bk"


    if [ ! -d "${HOME_DIR}/.local/bin" ]; then
        printf "%s/.local/bin directory is required for installation" "${HOME_DIR}"
        exit 1
    fi

    local keep_config="n"

    if [ -f "${install_path}" ]; then
        read -r -p "would you like to keep your current config? (y/n)" "keep_config"
    fi

    if [ "${keep_config}" != "y" ]; then
        uninstall
        mkdir "${CONFIG_DIR}"
        echo "{}" >> "${CONFIG_FILE}"
    else
        rm -f "${install_path}"
    fi

    printf "installing bk\n"
    cp "./bk.sh" "${install_path}"
    printf "bk installed!\n"
    exit 0
}

open() {
    if [ -z "${repository_name}" ]; then
        printf " -- %s" 'repository name parameter is required'
        exit 1
    fi

    local -r restic_mount_directory=$(get_config "repos.${repository_name}.RESTIC_MOUNT")
    local -r rclone_mount_directory=$(get_config "repos.${repository_name}.RCLONE_MOUNT")
    local -r rclone_remote_name=$(get_config "repos.${repository_name}.RCLONE_REMOTE_NAME")

    repository_password_credential=$(get_config "repos.${repository_name}.REPOSITORY_PASSWORD")
    repository_id_credential=$(get_config "repos.${repository_name}.REPOSITORY_ID")

    local -r repository_password=$(read_secret "${CONFIG_DIR}/${repository_password_credential}")
    local -r repository_id=$(read_secret "${CONFIG_DIR}/${repository_id_credential}")

    echo "restic mount: ${restic_mount_directory}"

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

close() {
    local -r rclone_mount_directory=$(get_config "repos.${repository_name}.RCLONE_MOUNT")

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

add_repository() {
    printf "please enter a name to save your repository under\n"
    read -r -p "repository name: " repository_name

    echo "${repository_name}"

    # TODO: If repository_name contains spaces, this fails
    if get_config "repos.${repository_name}" &> /dev/null; then
        printf "repository %s can not be created because it already exists\n" "${repository_name}"
        return 1
    fi

    local -r password_credential_file="${repository_name}-repository_password.cred"
    local -r repository_id_credential_file="${repository_name}-repository_id.cred"

    printf "please enter your restic repository ID and password\n"
    read -r -p "restic repository ID: " repository_id
    read -r -p "what is the repository password: " repository_password
    printf "\n"

    printf "please enter the directory that rclone will mount the repository files to, and the directory that restic will mount the opened backup to\n"
    read -r -p "what is the rclone mount directory: " rclone_mount
    read -r -p "what is the restic mount directory: " restic_mount
    read -r -p "what is the name of your (already configured) rclone remote:" rclone_remote_name

    create_secret "${repository_password}" "${CONFIG_DIR}" "${password_credential_file}"
    create_secret "${repository_id}" "${CONFIG_DIR}" "${repository_id_credential_file}"

    set_config "repos.${repository_name}.RCLONE_MOUNT" "${rclone_mount}"
    set_config "repos.${repository_name}.RESTIC_MOUNT" "${restic_mount}"
    set_config "repos.${repository_name}.RCLONE_REMOTE_NAME" "${rclone_remote_name}"
    set_config "repos.${repository_name}.REPOSITORY_PASSWORD" "${password_credential_file}"
    set_config "repos.${repository_name}.REPOSITORY_ID" "${repository_id_credential_file}"
}

list_repositories( ){
    local -r repositories=$(jq '.repos|keys | @sh' "${CONFIG_FILE}")

    for repository in ${repositories}; do
        printf "%s\n" "${repository}"
    done
}

main() {
    case $command in
        open) open ;;
        close) close ;;
        install) install ;;
        uninstall) uninstall ;;
        add) add_repository ;;
        list) list_repositories ;;
        *) usage ;;
    esac
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help) usage exit 0 ;;
    -pid | --restic-pid) restic_pid="$2"; shift ;;
    -v | --use_verbose) use_verbose=true; shift; shift ;;
    -r | --repository) repository_name="$2"; shift ;;
    open) set_command "open" ;;
    close) set_command "close" ;;
    install) set_command "install" ;;
    uninstall) set_command "uninstall" ;;
    add) set_command "add" ;;
    list) set_command "list" ;;
    *) usage ;;
    esac
    shift
done

main
