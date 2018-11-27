##
## this module contains functions to run and time certain kinds of
## operations.
##

timeit() {
    # params: binary runflags logfile stdin
    local -a runflags
    read -r -a runflags <<< "${2}"
    local timerformat='elapsed: %e s'
    local stdin="${4:-/dev/null}"
    debug "RUN: ./${1} ${runflags[*]} < ${stdin} &>> ${3}"
    if ! /usr/bin/time -p -o "timerfile" -f "${timerformat}" ./"${1}" "${runflags[@]}" < "${stdin}" &>> "${3}"; then
        error_handling
    fi
    __log_noredirect 4 "INFO" "  Time with profiler" >> "${3}"
    cat "timerfile" >> "${3}"
}

timeit_cuda() {
    # params: binary runflags logfile stdin
    local -a runflags
    read -r -a runflags <<< "${2}"
    local timerformat='elapsed: %e s'
    local stdin="${4:-/dev/null}"
    inf "Running with NVPROF"
    debug "RUN: ./${1} ${runflags[*]} < ${stdin} &> /dev/null"
    __log_noredirect 4 "INFO" "  CUDA profiler output:" >> "${3}"
    if ! nvprof -f --profile-api-trace all --track-memory-allocations on --unified-memory-profiling per-process-device -u ms --csv --log-file "${3}" ./"${1}" "${runflags[@]}" < "${stdin}" &> /dev/null; then
        error_handling
    fi
}
