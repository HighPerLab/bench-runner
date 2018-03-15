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
# - RUNFLAGS = '' optional
# - STDINS = '' optional
#
# NOTE: COMMENTS ARE NOT SUPPORTED, LINES CONTAINING key=value
#       PAIRS

shopt -s nullglob

FORCE=1
PROFDIR="${PWD}"

while getopts "hfd:" flag; do
    case $flag in
        f)
            FORCE=0
            ;;
        d)
            PROFDIR="${OPTARG}"
            ;;
        h)
            ;&
        ?)
            echo "Usage: $0 [-h|-f] [-d dir]" >&2
            exit 0
            ;;
    esac
done

PROFILES=( "${PROFDIR}"/*.profile )

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "No profiles found! Exiting..." >&2
    exit 1
fi

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

    IFS=',' read -r -a varients <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< ${CURRENTPROFILE[VARIENTS]})"
    IFS=',' read -r -a targets <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< ${CURRENTPROFILE[TARGETS]})"

    # copy build flags
    for varient in ${varients[@]}; do
        if [ -z "${CURRENTPROFILE[BUILDFLAGS_${varient//\'}]}" ]; then
            CURRENTPROFILE[BUILDFLAGS_${varient//\'}]="${CURRENTPROFILE[BUILDFLAGS]}"
        fi
        if [ "${#targets[@]}" -gt 1 ]; then
            IFS=',' read -r -a buildflags <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< ${CURRENTPROFILE[BUILDFLAGS_${varient//\'}]})"
            for (( i=0; i<${#targets[@]}; i++ )); do
                if [ -z "${buildflags[${i}]}" ]; then
                    buildflags[${i}]="${buildflags[0]}"
                fi
            done
            CURRENTPROFILE[BUILDFLAGS_${varient//\'}]="$(printf "(%s)" "${buildflags[*]}")"
        fi
    done

    # remove default buildflag
    unset 'CURRENTPROFILE[BUILDFLAGS]'

    PROFILEOUT=""

    for key in ${!CURRENTPROFILE[@]}; do
        PROFILEOUT+=$(printf "%s=%s\\\\n" "$key" "${CURRENTPROFILE[$key]}")
    done

    # generate sbatch script
    if [ -f "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh" -a ${FORCE} -eq 0 ]; then
        echo "Overwriting ${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
        sed -e "s:@NAME@:${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}:" -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:${PWD}:" run.sh.template > "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
        chmod +x "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
    elif [ ! -f "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh" ]; then
        echo "Generating ${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
        sed -e "s:@NAME@:${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}:" -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:${PWD}:" run.sh.template > "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
        chmod +x "${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
    else
        echo "Not updating ${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}.sh"
    fi
done
