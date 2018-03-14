#!/usr/bin/env bash

# THIS SCRIPT GENERATES SBATCH SCRIPTS FROM TEMPLATE
# FILE `run.sh.template`.

# THE OUTPUT FILE FORMAT IS `%benchsuite%-%benchname%.sh`

# Format:
# - BENCHSUITE = ''
# - BENCHNAME = ''
# - SOURCES = ()
# - INPUT = () optional, if give all data is copied to temp
# - TARGETS = () optional, defaults to TARGETS = ('seq')
# - VARIENTS = () optional, defaults to VARIENTS = ('default')
# - BUILDFLAGS = () is converted to BUILDFLAGS_default
#   or BUILDFLAGS_varient = () 
# - RUNFLAGS = ()
#
# NOTE: COMMENTS ARE NOT SUPPORTED, LINES CONTAINING key=value
#       PAIRS

shopt -s nullglob

PROFILES=( *.profile )

if [ ${#PROFILES} -eq 0 ]; then exit 1; fi

for profile in ${PROFILES[@]}; do
    declare -A CURRENTPROFILE
    while IFS== read -r key value; do
        CURRENTPROFILE[$key]=$value
    done < "$profile"

    # set default target
    if [ -z "${CURRENTPROFILE[TARGETS]}" ]; then
        CURRENTPROFILE[TARGETS]="('seq')"
    fi

    # set default varient
    if [ -z "${CURRENTPROFILE[VARIENTS]}" ]; then
        CURRENTPROFILE[VARIENTS]="('default')"
    fi

    IFS=' ()' read -r -a varients <<< ${CURRENTPROFILE[VARIENTS]}

    # copy build flags
    for varient in ${varients[@]}; do
        if [ -z "${CURRENTPROFILE[BUILDFLAGS_${varient//\'}]}" ]; then
            CURRENTPROFILE[BUILDFLAGS_${varient//\'}]="${CURRENTPROFILE[BUILDFLAGS]}"
        fi
    done

    # remove default buildflag
    unset 'CURRENTPROFILE[BUILDFLAGS]'

    PROFILEOUT=""

    for key in ${!CURRENTPROFILE[@]}; do
        PROFILEOUT+=$(printf "%s=%s\\\\n" "$key" "${CURRENTPROFILE[$key]}")
    done

    # generate sbatch script
    sed -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:'${PWD}':" run.sh.template > "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
    chmod +x "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
done
