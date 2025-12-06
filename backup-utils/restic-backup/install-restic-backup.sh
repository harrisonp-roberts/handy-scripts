#!/bin/bash
#
# #############################################################################
#
# Installs the restic backup script to the chosen directory, and configures
# a systemd service/timer to run it daily. Requires the provided restic-backup
# service and timer files.
#
# parameters
#   -r the URL of the repository REST server
#   -p the restic repository password
#   -s the directory the backup script will be installed into
#

. "../../templates/systemd-management.sh"

usage() {
    echo "./install-backup.sh -r [repository url] -p [repository password] -s [script installation directory]"
    exit 0
}

log() {
    local msg=$1
    printf "$(date) - ${msg}\n"
}

# global constants
readonly SERVICE_NAME="restic-backup.service"
readonly TIMER_NAME="restic-backup.timer"
readonly SCRIPT_NAME="restic-backup.sh"

# parameters
password=""
script_dir="/home/hroberts/.local/bin"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--password) password="$2"; shift ;;
        -s|--script-dir) script_dir="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

trap 'exit 1' SIGINT

# ensure parameters are all passed properly
if [ -z "$password" ] || [ -z "$script_dir" ]; then
    usage
fi

log "removing existing script installation"
rm -f "${script_dir}/${SCRIPT_NAME}"

log "installing script"
cp "${SCRIPT_NAME}" "${script_dir}/${SCRIPT_NAME}"

log "configuring service"
temp_service_name="tempservice"
temp_timer_name="temptimer"
cp "services/${SERVICE_NAME}" "${temp_service_name}"
cp "services/${TIMER_NAME}" "${temp_timer_name}"

sed -i -e "s#{RESTIC_PASSWORD}#${password}#g" "${temp_service_name}"

sudo setenforce 0
installService "$(realpath ${temp_timer_name})" "${TIMER_NAME}" "/etc/systemd/system"
installService "$(realpath ${temp_service_name})" "${SERVICE_NAME}" "/etc/systemd/system"

sudo systemctl start "${TIMER_NAME}"
sudo systemctl start "${SERVICE_NAME}"
sudo setenforce 1

log "cleaning up temporary files"
rm "${temp_service_name}"
rm "${temp_timer_name}"
