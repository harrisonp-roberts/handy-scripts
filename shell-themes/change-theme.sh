#!/bin/bash
###############################################################################
# This script is used to apply preconfigured themes to a shell using starship.
# Themes must be configured ahead of time and can be stored in a file with the
# name of it's theme. Themes are configured as key value pairs in the format
# `key = value`
# No quotes should be used. The following configuration keys are accepted.
# Background Colours
#   background1: the background colour of the command duration
#   background2: the background colour of the path
#   background3: the background colour of the git module
#   background4: the background colour of the clock
#   background5: the background colour of the battery indicator
#
# Foreground Colours
#   foreground1: the colour used by text and symbols
#

# Global Variables
SCRIPT_EXECUTION_PATH=$(realpath ${BASH_SOURCE})
SCRIPT_EXECUTION_DIRECTORY=$(dirname "${SCRIPT_EXECUTION_PATH}")
SCRIPT_INSTALLATION_PATH="${HOME}/.local/bin/change-theme"
THEME_HOME="${HOME}/.config/shell-theme-templates"
STARSHIP_TEMPLATE="starship.toml.template"

# Print usage information, available flags, etc
usage() {
    printf "This script is used to apply preconfigured themes to a shell using starship\n"
    printf "Usage:\n"
    printf "   change-theme [theme-name] [-i | --install] [-h | --help] [-l | --list]\n"
    printf " Run with the -l/--list flag to list available themes\n"
    printf " When running with the -i/--install flag, the script and it's themes will be installed to ${HOME}/.local/bin and ${HOME}/.config/shell-theme-templates\n"
    printf " Themes are configured in the repository's shell-theme-templates directory\n\n"
}

# Uninstalls the theme changer and it's themes
uninstall() {
    if [ -f "${SCRIPT_INSTALLATION_PATH}" ]; then
        printf "Removing old script version\n"
        rm -f "${SCRIPT_INSTALLATION_PATH}"
    fi

    if [ -d "$THEME_HOME" ]; then
        printf "Removing old theme templates\n"
        rm -r "${THEME_HOME}"
    fi
}

# Installs or reinstals the theme changer and it's themes
install() {
    local execution_directory=$(dirname "${SCRIPT_EXECUTION_PATH}")
    if [ $(realpath "${SCRIPT_EXECUTION_PATH}") = $(realpath "${SCRIPT_INSTALLATION_PATH}") ]; then
        printf "Script already installed\n"
        exit 0
    fi

    uninstall

    printf "Installing shell theme changer\n"
    printf "Installing script\n"
    cp  "${SCRIPT_EXECUTION_PATH}" "${SCRIPT_INSTALLATION_PATH}"

    printf "Installing theme templates\n"
    cp -r "${execution_directory}/shell-theme-templates" "${THEME_HOME}"
    printf "Installation complete!\n"

    exit 0
}

# lists themes installed into THEME_HOME
list-themes() {
    printf "Available themes:\n"
    ls "${THEME_HOME}" -I starship.toml.template
}

main() {
    if [ ! -f ${THEME_HOME}/${theme_name} ] || [ ${theme_name} = ${STARSHIP_TEMPLATE} ]; then
        printf "Theme $theme_name does not exist!\n"
        exit 0
    fi

    # Read template
    template=$(cat "${THEME_HOME}/${STARSHIP_TEMPLATE}")

    # set default colours to prevent errors
    background1="#111111"
    background2="#333333"
    background3="#555555"
    background4="#777777"
    background5="#999999"
    foreground1="#ffffff"
    divider=
    rightterminator=
    leftterminator=

    while read -r line
    do
        key=$(echo $line | cut -d '=' -f 1)
        value=$(echo $line | cut -d '=' -f 2)
        printf "Setting ${key} to ${value}"
        template=$(sed "s/${key}/${value}/g" <<< $template)
    done < "${THEME_HOME}/${theme_name}"

    template=$(sed "s/background1/${background1}/g" <<< $template)
    template=$(sed "s/background2/${background2}/g" <<< $template)
    template=$(sed "s/background3/${background3}/g" <<< $template)
    template=$(sed "s/background4/${background4}/g" <<< $template)
    template=$(sed "s/background5/${background5}/g" <<< $template)
    template=$(sed "s/foreground1/${foreground1}/g" <<< $template)
    template=$(sed "s/divider/${divider}/g" <<< $template)
    template=$(sed "s/rightterminator/${rightterminator}/g" <<< $template)
    template=$(sed "s/leftterminator/${leftterminator}/g" <<< $template)

    echo "${template}" > "${HOME}/.config/starship.toml"
}

theme_name="";
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -a|--apply) theme_name="$2"; shift ;;
        -l|--list) list-themes; exit 0 ;;
        -i|--install) install; exit 0 ;;
        -u|--uninstall) uninstall; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf "Unknown parameter passed: $1\n"; exit 1 ;;
    esac
    shift
done

main
