#
# Module provides function to parse commandline arguments
#

declare -A STAGES=( [build]=true [profile]=true [time]=true [trace]=true )
declare TARGET=true # we run all targets
declare MOUNT=false
declare VERBOSITY=0

usage() {
    cat <<- HERE >&2
    Usage: [-m] [-v...] [-S <STAGE>,...] [-t <TARGET>] [-h]
    -m              -- mount tmp dir (cluster specific)
    -t <TARGET>     -- use only target '<TARGET>'
    -v              -- verbosity (specify multiple times to increase)
    -S <STAGE>,...  -- which stage to complete (build, profile, time, and trace)
                       default: all
    -h              -- print this help message and exit
HERE
}

# param: arguments
argparse() {
    while getopts bhmt:S:v name; do
        case $name in
            S)
                local stage
                # zero out all stages
                for stage in "${!STAGES[@]}"; do
                    STAGES[$stage]=false
                done
                IFS=, read -ra stages <<< "${OPTARG}"
                for stage in "${stages[@]}"; do
                    if [[ ! "${!STAGES[*]}" =~ ${stage} ]]; then
                        echo "Given stage \`${stage}' is not valid!" >&2
                        exit 12
                    else
                        STAGES[$stage]=true
                    fi
                done
                ;;
            m)
                MOUNT=true
                ;;
            t)
                TARGET="${OPTARG}"
                ;;
            v)  # defaults to level 3 (warn)
                (( VERBOSITY += 1 ))
                ;;
            h)
                ;&
            ?)
                usage
                exit 0
                ;;
        esac
    done

    readonly STAGES
    readonly TARGET
    readonly MOUNT
    readonly VERBOSITY
}
