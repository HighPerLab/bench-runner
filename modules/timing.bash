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
    local stdin="${4:-/dev/null}"
    inf "Running with NVPROF"
    debug "RUN: ./${1} ${runflags[*]} < ${stdin} &> /dev/null"
    __log_noredirect 4 "INFO" "  CUDA profiler output:" >> "${3}"
    if ! nvprof -f --profile-api-trace all --track-memory-allocations on --unified-memory-profiling per-process-device -u ms --csv --log-file "${3}" ./"${1}" "${runflags[@]}" < "${stdin}" &> /dev/null; then
        error_handling
    fi
}

## with this function we can determine HtoD/DtoH bandwidths for the whole run.
## The following UNIX tools sequence can be used to get the averages:
##    grep HtoD example.csv.log | awk -F, '{ size+=$12; band+=$13; count+=1 } END { print size/count,band/count }'
nvprof_trace() {
    # params: binary runflags logfile stdin
    local -a runflags
    read -r -a runflags <<< "${2}"
    local stdin="${4:-/dev/null}"
    inf "Running with NVPROF GPU trace"
    __log_noredirect 4 "INFO" "  CUDA trace output:" >> "${3}"
    if ! nvprof -f --print-gpu-trace -u ms --csv --log-file "${3}" ./"${1}" "${runflags[@]}" < "${stdin}" &> /dev/null; then
        error_handling
    fi

}
