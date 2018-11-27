#
# Module provides function to parse commandline arguments
#

declare -A STAGES=( [build]=1 [run]=1 )
declare TARGET=true # we run all targets
declare MOUNT=false
declare VERBOSITY=0

usage() {
    cat <<- HERE >&2
    Usage: [-b] [-t <TARGET>] [-h]
    -b           -- build only
    -m           -- mount tmp dir (cluster specific)
    -t <TARGET>  -- use only target '<TARGET>'
    -v           -- verbosity (specify multiple times to increase)
    -h           -- print this help message
HERE
}

# param: arguments
argparse() {
    while getopts bhmt:v name; do
        case $name in
            b)
                STAGES[run]=0
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
