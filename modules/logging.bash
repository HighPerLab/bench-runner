##
## Simple logging mechanism for Bash
##
## Originally by: Michael Wayne Goodman <goodman.m.w@gmail.com>
##                <https://gist.github.com/goodmami/6556701>
##

## We support several verbosity levels:
## SILENT   - 0
## CRITICAL - 1
## ERROR    - 2
## WARNING  - 3
## INFO     - 4
## DEBUG    - 5

declare __log_verbose=3 # default to show warnings
declare __log_output=""
declare __log_init=false # flag

# param: [verbosity-level] [logfile]
loginit() {
    __log_verbose=$(( $1 + __log_verbose ))
    __log_output=${2:-${__log_output}}
    if [ -n "$__log_output" ]; then
        # logging stream (fd 3) to LOGFILE and STDERR
        exec 3> >(tee -a "$__log_output" >&2)
    else
        # logging stream (file descriptor 3) defaults to STDERR
        exec 3>&2
    fi
    __log_init=true
    readonly __log_init
    readonly __log_output
    readonly __log_verbose
}

notify() { __log 0 "NOTE" "$1"; } # Always prints
critical() { __log 1 "CRITICAL" "$1"; exit 1; }
error() { __log 2 "ERROR" "$1"; }
warn() { __log 3 "WARNING" "$1"; }
inf() { __log 4 "INFO" "$1"; } # "info" is already a command
debug() { __log 5 "DEBUG" "$1"; }

__log_noredirect() {
    if [[ "$__log_verbose" -ge "$1" ]]; then
        datestring=$(date +'%d-%m-%y %H:%M:%S')
        # Expand escaped characters, wrap at 80 chars, indent wrapped lines
        printf "[$datestring](%-8s): %s\\n" "$2" "$3" | fold -w80 -s | sed '2~1s/^/-----------------------------: /'
    fi
}

__log() {
    if [[ "$__log_init" == true ]]; then
        __log_noredirect "$@" >&3
    else
        __log_noredirect "$@" >&2
    fi
}

arraylog() {
    if [[ "$__log_init" == true ]]; then
        __log_array "$@" >&3
    else
        __log_array "$@" >&2
    fi
}

# special printer for pairs of data
__log_array() {
    datestring=$(date +'%d-%m-%y %H:%M:%S')
    printf "[$datestring](%-8s):\\n" "ARRAYLOG"
    for a in "$@"; do
        printf '        %s\n' "${a}" | fold -w80 -s | sed '2~1s/^/        /'
    done
}

# this is a wrapper around any command to pipe something to the logfile and/or stderr
capture() {
    if [[ "$__log_init" == true ]]; then
        "$@" 2>&1 >&3
    else
        "$@" >&2
    fi
}
