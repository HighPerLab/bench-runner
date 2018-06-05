#!/usr/bin/env bash

# THIS SCRIPT GENERATES SBATCH SCRIPTS FROM TEMPLATE
# FILE `run.sh.template`.

# THE OUTPUT FILE FORMAT IS `%benchsuite%-%benchname%.sh`

# Format:
# - BENCHSUITE = ''
# - BENCHNAME = ''
# - MODE=AUTO          optional, choices: AUTO, MANUAL; default is AUTO
# - TIMELIMIT=MINUTES  optional, defaults to 60 minutes
# - SOURCES = ()
# - INPUTS = ()        optional, if give all data is copied to temp
# - TARGETS = ()       optional, defaults to TARGETS = ('seq')
# - VARIENTS = ()      optional, defaults to VARIENTS = ('default')
# - BUILDFLAGS = ()    is converted to BUILDFLAGS_default
#     or BUILDFLAGS_varient = ()
# - RUNFLAGS = ''      optional
# - STDINS = ''        optional

shopt -s nullglob

FORCE=false
VERBOSE=false
PROFDIR="${PWD}"

while getopts "vhfd:" flag; do
    case $flag in
        f)
            FORCE=true
            ;;
        d)
            PROFDIR="${OPTARG}"
            ;;
        v)
            VERBOSE=true
            ;;
        h)
            ;&
        ?)
            echo "Usage: $0 [-h|-f] [-d dir]" >&2
            exit 0
            ;;
    esac
done

verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "$1" >&2
    fi
}

PROFILES=( "${PROFDIR}"/*.profile )

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "No profiles found! Exiting..." >&2
    exit 1
fi

for profile in ${PROFILES[@]}; do
    declare -A CURRENTPROFILE
    while IFS== read key value; do
        CURRENTPROFILE[$key]=$value
        verbose "  [$key] = $value" >&2
    done < <(sed -e 's/\(^#.*\|[^\\]#.*\)//' -e 's/\&/\\\\&/g' -e 's/\\$/\\\\n\\/' -e '/^\s*$/d' "$profile")
    # remove handle comments (we can still
    # escape (\#) hash symbol) and ampersand

    BUILD_MANUAL=false
    skip=false
    FULL_NAME="${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}"
    SCRIPT_NAME="${FULL_NAME}.run.sh"
    TIMELIMIT="60"

    # get time limit
    if [ ! -z "${CURRENTPROFILE[TIMELIMIT]}" ]; then
        TIMELIMIT="${CURRENTPROFILE[TIMELIMIT]//\'}"
    fi

    # get build mode
    if [ "x${CURRENTPROFILE[MODE]//\'}" = "xMANUAL" ]; then
        BUILD_MANUAL=true
        CURRENTPROFILE[MODE]="'MANUAL'"
    else
        CURRENTPROFILE[MODE]="'AUTO'"
    fi

    # check that we have build for MANUAL mode
    if [ -z "${CURRENTPROFILE[BUILD]}" -a "$BUILD_MANUAL" = true ]; then
        echo "Can't generate script with manual build without \`BUILD' function" >&2
        echo "  Skipping '${SCRIPT_NAME}'" >&2
        skip=true
    elif [ ! -z "${CURRENTPROFILE[BUILD]}" -a "$BUILD_MANUAL" = false ]; then
        echo "Warning: profile specifies BUILD but is in AUTO mode!"
        unset 'CURRENTPROFILE[BUILD]'
    fi
    
    # check that we have run for MANUAL mode
    if [ -z "${CURRENTPROFILE[RUN]}" -a "$BUILD_MANUAL" = true ]; then
        echo "Can't generate script with manual build without \`RUN' function" >&2
        echo "  Skipping '${SCRIPT_NAME}'" >&2
        skip=true
    elif [ ! -z "${CURRENTPROFILE[RUN]}" -a "$BUILD_MANUAL" = false ]; then
        echo "Warning: profile specifies RUN but is in AUTO mode!"
        unset 'CURRENTPROFILE[RUN]'
    fi

    if [ "$skip" = false ]; then
        if [ "${BUILD_MANUAL}" = true ]; then
            # we unset most key-value pairs
            IFS=',' read -r -a varients <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< ${CURRENTPROFILE[VARIENTS]})"
            for varient in ${varients[@]}; do
                unset "CURRENTPROFILE[BUILDFLAGS_${varient//\'}]"
            done
            unset 'CURRENTPROFILE[TARGETS]'
            unset 'CURRENTPROFILE[VARIENTS]'
        else
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
        fi

        PROFILEOUT=""

        for key in ${!CURRENTPROFILE[@]}; do
            if [ "x$key" = "xBUILD" -o "x$key" = "xRUN" ]; then
                # output function and body
                PROFILEOUT+=$(printf "%s(){%s}\\\\n" "${key,,}" "${CURRENTPROFILE[$key]//\'}")
            else
                # output key-value pair as is
                PROFILEOUT+=$(printf "%s=%s\\\\n" "$key" "${CURRENTPROFILE[$key]}")
            fi
        done

        # generate sbatch script
        if [ -f "${SCRIPT_NAME}" -a "${FORCE}" = true ]; then
            echo "Overwriting ${SCRIPT_NAME}"
            sed -e "s:@NAME@:${FULL_NAME}:" -e "s:@TIMELIMIT@:${TIMELIMIT}:" -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:${PWD}:" run.sh.template > "${SCRIPT_NAME}"
            chmod +x "${SCRIPT_NAME}"
        elif [ ! -f "${SCRIPT_NAME}" ]; then
            echo "Generating ${SCRIPT_NAME}"
            sed -e "s:@NAME@:${FULL_NAME}:" -e "s:@TIMELIMIT@:${TIMELIMIT}:" -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:${PWD}:" run.sh.template > "${SCRIPT_NAME}"
            chmod +x "${SCRIPT_NAME}"
        else
            echo "Not updating ${SCRIPT_NAME}"
        fi
    fi

    # clear variables
    unset CURRENTPROFILE
    unset targets
    unset varients
    unset buildflags
done
