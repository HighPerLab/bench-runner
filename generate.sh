#!/usr/bin/env bash

# THIS SCRIPT GENERATES SBATCH SCRIPTS FROM TEMPLATE
# FILE `run.sh.template`.

# THE OUTPUT FILE FORMAT IS `%benchsuite%-%benchname%.sh`

# Format:
# - BENCHSUITE = ''
# - BENCHNAME = ''
# - MODE=AUTO          optional, choices: AUTO, MANUAL, MAKE; default is AUTO
# - COMPILER=''        set teh compiler to be used
# - TIMELIMIT=MINUTES  optional, defaults to 60 minutes
# - SOURCES = ()       note, in the case of MAKE, the first source is assumend to be
#                      a directory containing the Makefile. Any further list directories
#                      are only copied over, not traversed!
# - INPUTS = ()        optional, if give all data is copied to temp
# - TARGETS = ()       optional, defaults to TARGETS = ('seq')
# - VARIENTS = ()      optional, defaults to VARIENTS = ('default')
# - BUILDFLAGS = ()    is converted to BUILDFLAGS_default
#     or BUILDFLAGS_varient = ()
# - RUNFLAGS = ''      optional
# - REPRANGE = ()      optional, contains a start, end, and increment value (think seq)
# - STDINS = ''        optional

shopt -s nullglob

FORCE=false
OVERRIDE=false
PROFDIR="${PWD}"
RDIR="${PWD}"
# FIXME we want to point this to something more generic
TDIR="sac-template"
TARGETS=()
VARIANTS=()
VERBOSITY=0
DOSYSINFO=false
readonly _batchtypes=('slurm' 'pbs')
BATCHSYS=${_batchtypes[0]}
readonly VERSION='0.7.0'

while getopts "vhfib:d:V:r:t:T:" flag; do
    case $flag in
        b)
            if [[ "${_batchtypes[*]}" =~ ${OPTARG} ]]; then
                BATCHSYS="${OPTARG}"
            else
                echo "Value \`${OPTARG}' is not valid batch system type!" >&2
                exit 12
            fi
            ;;
        d)
            PROFDIR="${OPTARG}"
            ;;
        f)
            FORCE=true
            ;;
        i)
            DOSYSINFO=true
            break
            ;;
        r)
            RDIR="$(readlink -f -- "${OPTARG}")"
            ;;
        t)
            TDIR="$(readlink -f -- "${OPTARG}")"
            ;;
        T)  # restrict targets
            TARGETS+=("${OPTARG}")
            OVERRIDE=true
            ;;
        v)  # defaults to level 3 (warn)
            (( VERBOSITY += 1 ))
            ;;
        V)  # restrict varients
            VARIANTS+=("${OPTARG}")
            OVERRIDE=true
            ;;
        h)
            ;&
        ?)
            echo "Usage: $0 [-h|-f|-v...] [-b bsys] [-r dir] [-t dir] [-T target] [-V variant] [-d dir]" >&2
            echo "version: ${VERSION}" >&2
            echo "" >&2
            echo "Generate batch system compatible scripts based upon profile files and a script template" >&2
            echo "" >&2
            echo "More help:" >&2
            printf "%5s  %s\\n" "-b" "batch system to generate for (default: slurm, choices: slurm, pbs)" >&2
            printf "%5s  %s\\n" "-d" "directory will profile file(s)" >&2
            printf "%5s  %s\\n" "-f" "force overwrite of existing sbatch scripts" >&2
            printf "%5s  %s\\n" "-h" "this help message and exit" >&2
            printf "%5s  %s\\n" "-i" "display system info and exit" >&2
            printf "%5s  %s\\n" "-r" "root directory (where bench-runner files are)" >&2
            printf "%5s  %s\\n" "-t" "directory with the sbatch template" >&2
            printf "%5s  %s\\n" "-T" "restrict profile generation to specified target" >&2
            printf "%5s  %s\\n" "-v" "increase verbosity (specify multiple times for higher verbosity)" >&2
            printf "%5s  %s\\n" "-V" "restrict profile generation to specified variant" >&2
            exit 0
            ;;
    esac
done

if [ ! -d "${RDIR}/modules" ]; then
    echo "Can't find shell modules! Exiting..." >&2
    exit 1
fi

# get external functions
for s in ${RDIR}/modules/*.bash; do
    # shellcheck source=/dev/null
    source "${s}"
done

# initiat logging
loginit $VERBOSITY

if [ "${DOSYSINFO}" = true ]; then
    sysinfo
    exit 0
fi

if [ ! -d "${RDIR}/${TDIR}" ]; then
    critical "Template dir could not be found! Exiting..."
    exit 1
fi

# again we through generics out of the window...woo!
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=('seq')
fi
if [ ${#VARIANTS[@]} -eq 0 ]; then
    VARIANTS=('default')
fi

if [ ! -d "${PROFDIR}" ]; then
    critical "Profile dir could not be found! Exiting..."
    exit 1
fi

PROFILES=( "${PROFDIR}"/*.profile )

# FIXME again we ignore generics for the moment
#COMPILER=$(command -v sac2c_p) || critical "Unable to locate sac2c_p binary, exiting..."

if [ ${#PROFILES[@]} -eq 0 ]; then
    critical "No profiles found! Exiting..."
    exit 1
fi

# we compile the bash modules into a single file
BMODF="$(mktemp)"
cat "${RDIR}"/modules/*.bash > "${BMODF}"

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
    BUILD_MAKE=false
    skip=false
    FULL_NAME="${CURRENTPROFILE[BENCHSUITE]//\'}-${CURRENTPROFILE[BENCHNAME]//\'}"
    SCRIPT_NAME="${FULL_NAME}.run.sh"
    # the timelimit is set to two and a half days (in minutes)
    TIMELIMIT="3880"

    # get time limit
    if [ -n "${CURRENTPROFILE[TIMELIMIT]}" ]; then
        TIMELIMIT="${CURRENTPROFILE[TIMELIMIT]//\'}"
    fi

    # get build mode
    if [ "x${CURRENTPROFILE[MODE]//\'}" = "xMANUAL" ]; then
        BUILD_MANUAL=true
        CURRENTPROFILE[MODE]="'MANUAL'"
    elif [ "x${CURRENTPROFILE[MODE]//\'}" = "xMAKE" ]; then
        BUILD_MAKE=true
        CURRENTPROFILE[MODE]="'MAKE'"
        CURRENTPROFILE[COMPILER]="'make'"
    else
        CURRENTPROFILE[MODE]="'AUTO'"
    fi

    # check that we have the compiler set
    if [ -z "${CURRENTPROFILE[COMPILER]}" ]; then
        # we'll go back to generics later
        error "Can't generate script without \`COMPILER' being defined. Skipping '${SCRIPT_NAME}'"
        skip=true
        #CURRENTPROFILE[COMPILER]="'${COMPILER}'"
    fi

    # check that we have build for MANUAL mode
    if [ -z "${CURRENTPROFILE[BUILD]}" ] && [ "$BUILD_MANUAL" = true ]; then
        error "Can't generate script with manual build without \`BUILD' function. Skipping '${SCRIPT_NAME}'"
        skip=true
    elif [ -n "${CURRENTPROFILE[BUILD]}" ] && [ "$BUILD_MANUAL" = false ]; then
        warn "Profile specifies BUILD but is in AUTO mode!"
        unset 'CURRENTPROFILE[BUILD]'
    fi

    # check that we have run for MANUAL mode
    if [ -z "${CURRENTPROFILE[RUN]}" ] && [ "$BUILD_MANUAL" = true ]; then
        error "Can't generate script with manual build without \`RUN' function. Skipping '${SCRIPT_NAME}'"
        skip=true
    elif [ -n "${CURRENTPROFILE[RUN]}" ] && [ "$BUILD_MANUAL" = false ]; then
        warn "Profile specifies RUN but is in AUTO mode!"
        unset 'CURRENTPROFILE[RUN]'
    fi

    # check that we have REPRANGE to define the range, default is 5 iterations
    if [ -z "${CURRENTPROFILE[REPRANGE]}" ]; then
        CURRENTPROFILE[REPRANGE]="('1' '5' '1')"
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
            if [ -z "${CURRENTPROFILE[TARGETS]}" ] || [ "$OVERRIDE" = true ]; then
                _t=$(printf "'%s' " "${TARGETS[@]}")
                # we need to remove the trailing space
                CURRENTPROFILE[TARGETS]="(${_t% })"
            fi

            # set default varient
            if [ -z "${CURRENTPROFILE[VARIENTS]}" ] || [ "$OVERRIDE" = true ]; then
                _t=$(printf "'%s' " "${VARIANTS[@]}")
                # we need to remove the trailing space
                CURRENTPROFILE[VARIENTS]="(${_t% })"
            fi

            IFS=',' read -r -a varients <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< "${CURRENTPROFILE[VARIENTS]}")"
            IFS=',' read -r -a targets <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< "${CURRENTPROFILE[TARGETS]}")"

            # copy build flags
            for varient in "${varients[@]}"; do
                if [ -z "${CURRENTPROFILE[BUILDFLAGS_${varient//\'}]}" ]; then
                    CURRENTPROFILE[BUILDFLAGS_${varient//\'}]="${CURRENTPROFILE[BUILDFLAGS]}"
                fi
                if [ "${#targets[@]}" -gt 1 ]; then
                    IFS=',' read -r -a buildflags <<< "$(sed -e "s/' /',/g" -e "s/[()]//g" <<< "${CURRENTPROFILE[BUILDFLAGS_${varient//\'}]}")"
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
            sed -e "/## BATCH/ r ${RDIR}/${TDIR}/${BATCHSYS}.in" -e "/## ENVMODULES/ r ${RDIR}/${TDIR}/envmodules.in" \
                -e "/## GLOBALS/ r ${RDIR}/${TDIR}/globals.in" -e "/## BASHMODULES/ r ${BMODF}" \
                -e "/## SCRIPT/ r ${RDIR}/${TDIR}/script.sh.in" "${RDIR}/basic-template.sh.in" |\
            sed -e "s:@NAME@:${FULL_NAME}:" -e "s:@TIMELIMIT@:${TIMELIMIT}:" \
                -e "s:@PROFILE@:${PROFILEOUT}:" -e "s:@RUNNERDIR@:${RDIR}:" -e "s:@PWD@:${PWD}:" > "${SCRIPT_NAME}"
            chmod +x -- "${SCRIPT_NAME}"
        else
            inf "Not updating ${SCRIPT_NAME}"
        fi
    fi

    # clear variables
    unset _t
    unset CURRENTPROFILE
    unset PROFILEOUT
    unset targets
    unset varients
    unset buildflags
done

# delete temp file
[ -f "${BMODF}" ] && rm "${BMODF}"
