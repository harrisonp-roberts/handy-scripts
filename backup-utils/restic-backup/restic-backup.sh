#!/bin/bash
#
###############################################################################
#
# Script that performs a restic backup of the system. It expects the restic
# backend API (which is served by rclone) to be available at
# rest:http://localhost:8080/

# Constants
readonly EXCLUDES="
/home/hroberts/Games
/home/hroberts/.local/share/Steam
"
readonly RCLONE_STORAGE_LOCATION="hetzner-storage-box:restic-desktop"
readonly HOME_DIR="/home/hroberts"
readonly restic_repository="rest:http://localhost:8080/"
readonly temp_excludes="$(mktemp)"

# Globals
rclone_pid=""

log() {
    local msg=$1
    printf "${msg}\n"
}

launch_rclone_server() {
    log "launching rclone server"
    rclone serve restic -v "${RCLONE_STORAGE_LOCATION}" &
    rclone_pid=$!
    log "waiting for server to launch..."
    sleep 5

    log "rclone server launched with pid ${rclone_pid}"
}

do_backup() {
    mkdir -p "${HOME_DIR}/.cache/restic-backup"
    touch "${temp_excludes}"
    echo "${EXCLUDES}" > "${temp_excludes}"

    log "performing backup"
    restic -r "${restic_repository}" backup ${HOME_DIR} /etc --exclude-file=${temp_excludes}

    log "cleaning cache"
    rm -r "${HOME_DIR}/.cache/restic-backup/"
}

cleanup() {
    log "backup interrupted, cleaning up"
    rm "${temp_excludes}"

    if [ ! -z "${rclone_pid}" ]; then
      kill -15 "${rclone_pid}"
    fi
}

trap 'cleanup' SIGINT
trap 'cleanup' SIGTERM

readonly restic_password="${1}"
export RESTIC_PASSWORD="${restic_password}"

main() {
    launch_rclone_server
    do_backup

    kill -15 "${rclone_pid}"
}

main
