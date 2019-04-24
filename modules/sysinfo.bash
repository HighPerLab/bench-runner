##
## This module provides functions to get basic system information.
##
##   We make use of inxi primarily.
##

# inxi surprisingly does not provide information on actual system-wide
# memory state, instead it provides the raw output from dmidecode which
# only shows information about the hardware as derived by the BIOS.
meminfo() {
    echo "Memory:" >&3
    free --human --total >&3
}

# when calling this, we redirect the output to FD 3 (as per logging)
sysinfo() {
    local inxi

    inxi="$(command -v inxi)"
    if [ -z "$inxi" ]; then
        echo "Unable to find inxi!"
        exit 20
    else
        "$inxi" -c 0 -v 4 >&3
        meminfo
    fi
}

# get number of cores (including hyper-thread cores)
get_logical_core_count() {
    local cores
    cores=$(lscpu -p | grep -c -E -v '^#')
    echo "${cores}"
}

# get number of physical cores (excluding hyper-thread cores)
get_physical_core_count() {
    local cores
    cores=$(lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)
    echo "${cores}"
}
