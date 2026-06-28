#!/bin/bash
#
###############################################################################
#
# various examples of working with systemd services. functions are used as
# examples, many examples should be implemented within scripts as one liners
# instead of functions.
#

# checks if a service is enabled
# parameters
#   1. name of service to check status of
# returns
#   status code 0 if enabled, nonzero if disabled (or not exists)
check_enabled() {
    local service_name="${1}"
    systemctl is-enabled --quiet ${service_name} > /dev/null 2>&1
}

# checks if a service exists
# parameters/
#   1. name of service to check (e.g. my-service.service, my-service.timer)
# returns
#   status code 0 if exists, nonzero if not exists
service_exists() {
    local service_name="${1}"
    if [[ $(systemctl list-units --all -t service --full --no-legend "${service_name}" | sed 's/^\s*//g' | cut -f1 -d' ') == "${service_name}" ]]; then
        return 0
    else
        return 1
    fi
}

# uninstalls a service if it exists.
# assumes that services are installed in /etc/systemd/system unless specified
# parameters
#   1. name of service to uninstall
#   2. (optional) directory to install the service in
uninstall_service() {
    local service_name="${1}"
    local service_path="/etc/systemd/system/${service_name}"

    if [ ! -z "${2}" ]; then
        service_path="${2}/${service_name}"
    fi

    check_enabled "${service_name}" && {
        log "disabling service"
        sudo systemctl stop "${service_name}"
        sudo systemctl disable "${service_name}"
    }

    service_exists "${service_name}" && {
        log "deleting service "${service_path}
        sudo rm "${service_path}"
        sudo systemctl daemon-reload
    }
}

# installs or reinstalls a service. will overwrite existing service if exists
# does not automatically start the service
# assumes that service name is the same template name unless specified
# assumes that service is installed in /etc/systemd/system unless specified
#
# parameters
#   1. path of the template service that will be installed
#   2. (optional) service name. must be provided if specifying install directory
#   2. (optional) directory to install the service in
#
# note: as of the time of creating this, there is a bug in systemd that causes
# an SELinux denial. prior to calling this, setenforce 0. after calling
# setenforce 1
install_service() {
    local source_service_path="${1}"
    local target_service_name=$(basename "${source_service_path}")
    local target_service_directory="/etc/systemd/system/"

    if [ ! -f "${source_service_path}" ]; then
        log "source service does not exist"
        return 1
    fi

    if [ ! -z "${2}" ] && [ -z "${3}" ]; then
        log "target service name and path must both be empty or specified."
        return 1
    fi

    if [ ! -z "${2}" ] && [ ! -z "${3}" ]; then
        target_service_name="${2}"
        target_service_directory="${3}"
        mkdir -p "${target_service_directory}"
    fi

    local target_service_path="${target_service_directory}/${target_service_name}"
    log "installing service ${target_service_name} to ${target_service_directory}"

    uninstall_service "${SERVICE_NAME}" "${target_service_directory}"

    sudo cp "${source_service_path}" "${target_service_path}"
    sudo systemctl enable "${target_service_path}"
    sudo systemctl daemon-reload
}


create_secret() {
    local -r secret="$1"
    local -r credential_directory="$2"
    local -r credential_name="$3"

    if [ ! -d "${credential_directory}" ]; then
        printf "directory '%s' does not exist" "${credential_directory}" >&2
        return 1
    fi

    echo "${secret}" | sudo systemd-creds encrypt --with-key=tpm2 --name="${credential_name}" - "${credential_directory}/${credential_name}"
}

read_secret() {
    local -r credential_filepath="$1"

    if [ ! -f "${credential_filepath}" ]; then
        printf "credential file '%s' does not exist\n" "${credential_filepath}" >&2
        return 1
    fi

    local -r decrypted_secret=$(sudo systemd-creds decrypt --no-ask-password "${credential_filepath}" 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "${decrypted_secret}"
    else
        printf "failed to read secret at '%s'" "${credential_filepath}"
    fi
}