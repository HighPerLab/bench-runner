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

if [ -n "$LOGFILE" ]; then
	exec 3> >(tee -a "$LOGFILE" >&2)
    # logging stream (fd 3) to LOGFILE and STDERR
else
	exec 3>&2 # logging stream (file descriptor 3) defaults to STDERR
fi

VERBOSITY=${VERBOSITY:=3} # default to show warnings

notify() { __log 0 "NOTE" "$1"; } # Always prints
critical() { __log 1 "CRITICAL" "$1"; }
error() { __log 2 "ERROR" "$1"; }
warn() { __log 3 "WARNING" "$1"; }
inf() { __log 4 "INFO" "$1"; } # "info" is already a command
debug() { __log 5 "DEBUG" "$1"; }
__log_noredirect() {
    if [ "$VERBOSITY" -ge "$1" ]; then
        datestring=$(date +'%d-%m-%y %H:%M:%S')
        # Expand escaped characters, wrap at 80 chars, indent wrapped lines
        printf "[$datestring](%-8s): %s\\n" "$2" "$3" | fold -w80 -s | sed '2~1s/^/-----------------------------: /'
    fi
}
__log() {
    __log_noredirect "$@" >&3
}
# special printer for pairs of data
arraylog() {
    datestring=$(date +'%d-%m-%y %H:%M:%S')
    printf "[$datestring](%-8s):\\n" "ARRAYLOG" >&3
    for a in "$@"; do
        printf '        %s\n' "${a}" | fold -w80 -s | sed '2~1s/^/        /' >&3
    done
}
# this is a wrapper around any command to pipe something to the logfile and/or stderr
capture() {
    "$@" 2>&1 >&3
}
