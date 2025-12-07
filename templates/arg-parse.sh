#!/bin/bash
#
###############################################################################
# 
# A template for parsing named arguments in a bash script. Arguments can either
# be a flag without a value, or a parameter with a value.
# 

value1=""
value2=""
flag1=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -a|--arg-a) value1="$2"; shift ;;
        -b|--arg-b) value2="$2"; shift ;;
        -f|--flag) home_dir=true; shift; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done