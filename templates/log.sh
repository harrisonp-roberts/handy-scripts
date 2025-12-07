#!/bin/bash
#
###############################################################################

# Contains standard logging output for
# 1. Standard logging + tee to a file
#   for scripts executed by user, when logs will be accessed frequently
#
# 2. Standard logging to stdout
#   for scripts that are executed by user when logs will not be needed after
#   execution
#
# 3. Standard logging to stdout, without date
#   for scripts that are executed as a service, logs are handled by syslog and
#   date is added automatically
#


# output to console and log file
# parameters
#   1: message to log
# global parameters:
#   LOG_FILE: file for log output
log() {
    local msg=$1
    printf "$(date) - ${msg}\n" | tee -a ${LOG_FILE}
}

# output to console with date
# parameters
#   1. message to log
log() {
    local msg=$1
    printf "$(date) - ${msg}\n"
}

# output to console without date
# parameters
#   1. message to log
log() {
    local msg=$1
    printf "${msg}\n"
}
