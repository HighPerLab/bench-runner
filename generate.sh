#!/usr/bin/env bash

# THIS SCRIPT GENERATES SBATCH SCRIPTS FROM TEMPLATE
# FILE `run.sh.template`.

# THE OUTPUT FILE FORMAT IS `%benchsuite%-%benchname%.sh`

# Format:
# - BENCHSUITE = ''
# - BENCHNAME = ''
# - MODE=AUTO          optional, choices: AUTO, MANUAL; default is AUTO
# - COMPILER=''        set teh compiler to be used
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
PROFDIR="${PWD}"

# get external functions
for s in modules/*.bash; do
    # shellcheck source=/dev/null
    source "${s}"
done

while getopts "vhfid:" flag; do
    case $flag in
        f)
            FORCE=true
            ;;
        d)
            PROFDIR="${OPTARG}"
            ;;
        v)  # defaults to level 3 (warn)
            (( VERBOSITY += 1 ))
            ;;
        i)
            sysinfo
            exit 0
            ;;
        h)
            ;&
        ?)
            echo "Usage: $0 [-h|-f|-v...] [-d dir]" >&2
            exit 0
            ;;
    esac
done

PROFILES=( "${PROFDIR}"/*.profile )

# FIXME again we ignore generics for the moment
COMPILER=$(which sac2c_p) || critical "Unable to locate sac2c_p binary, exiting..."

if [ ${#PROFILES[@]} -eq 0 ]; then
    critical "No profiles found! Exiting..."
    exit 1
fi

for profile in "${PROFILES[@]}"; do
    declare -A CURRENTPROFILE
    # shellcheck disable=SC2162
    while IFS='=' read key value; do
        CURRENTPROFILE[$key]=$value
        debug "[$key] = $value"
    done < <(sed -e 's/\(^#.*\|[^\\]#.*\)//' -e 's/\&/\\\\&/g' -e 's/\\$/\\\\n\\/' -e '/^\s*$/d' "$profile")
    # remove handle comments (we can still
    # escape (\#) hash symbol and ampersand)

    BUILD_MANUAL=false
    skip=false
    FULL_NAME="${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}"
    SCRIPT_NAME="${FULL_NAME}.run.sh"
    # the timelimit is set to two and a half days (in minutes)
    TIMELIMIT="3880"

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

    # check that we have the compiler set
    if [ -z "${CURRENTPROFILE[COMPILER]}" ]; then
        # we'll go back to generics later
        #error "Can't generate script without \`COMPILER' being defined. Skipping '${SCRIPT_NAME}'"
        #skip=true
        CURRENTPROFILE[COMPILER]="'${COMPILER}'"
    fi

    # check that we have build for MANUAL mode
    if [ -z "${CURRENTPROFILE[BUILD]}" ] && [ "$BUILD_MANUAL" = true ]; then
        error "Can't generate script with manual build without \`BUILD' function. Skipping '${SCRIPT_NAME}'"
        skip=true
    elif [ ! -z "${CURRENTPROFILE[BUILD]}" ] && [ "$BUILD_MANUAL" = false ]; then
        warn "Profile specifies BUILD but is in AUTO mode!"
        unset 'CURRENTPROFILE[BUILD]'
    fi

    # check that we have run for MANUAL mode
    if [ -z "${CURRENTPROFILE[RUN]}" ] && [ "$BUILD_MANUAL" = true ]; then
        error "Can't generate script with manual build without \`RUN' function. Skipping '${SCRIPT_NAME}'"
        skip=true
    elif [ ! -z "${CURRENTPROFILE[RUN]}" ] && [ "$BUILD_MANUAL" = false ]; then
        warn "Profile specifies RUN but is in AUTO mode!"
        unset 'CURRENTPROFILE[RUN]'
    fi

    if [ "$skip" = false ]; then
        if [ "${BUILD_MANUAL}" = true ]; then
            # we unset most key-value pairs
            IFS=',' read -r -a varients <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< "${CURRENTPROFILE[VARIENTS]}")"
            for varient in "${varients[@]}"; do
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
            for varient in "${varients[@]}"; do
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

        for key in "${!CURRENTPROFILE[@]}"; do
            if [ "x$key" = "xBUILD" ] || [ "x$key" = "xRUN" ]; then
                # output function and body
                PROFILEOUT+=$(printf "%s(){%s}\\\\n" "${key,,}" "${CURRENTPROFILE[$key]//\'}")
            else
                # output key-value pair as is
                PROFILEOUT+=$(printf "%s=%s\\\\n" "$key" "${CURRENTPROFILE[$key]}")
            fi
        done

        # generate sbatch script
        if [ ! -f "${SCRIPT_NAME}" ] || [ "${FORCE}" = true ]; then
            sed -e "s:@NAME@:${FULL_NAME}:" -e "s:@TIMELIMIT@:${TIMELIMIT}:" -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@PWD@:${PWD}:" run.sh.in > "${SCRIPT_NAME}"
            chmod +x -- "${SCRIPT_NAME}"
        else
            inf "Not updating ${SCRIPT_NAME}"
        fi
    fi

    # clear variables
    unset CURRENTPROFILE
    unset PROFILEOUT
    unset targets
    unset varients
    unset buildflags
done
