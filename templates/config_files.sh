#!/bin/bash

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
        exit 1
    fi 

    mv "${temp_config_file}" "${config_file}"
}

# retrieve a property from a JSON configuration file
#
# mandatory parameters
#   1. the path of the key that will be created or updated in the format of "path.to.key"
#   2. (optional) the path to the configuration file to retrieve the value from
get_config() {
    local -r key_path="$1"
    local -r config_file="${CONFIG_FILE:-$3}"

    local -r value=$(jq ".${key_path}" "${config_file}")
    echo "${value}"
}