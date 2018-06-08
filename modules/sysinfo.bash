##
## This module provides functions to get basic system information.
##
##   We make use of ixni primarily.
##

# FIXME we really need a better way of specifying where to find this stuff
if [ -n "$LOCALDIR" ]; then
    IXNI="$LOCALDIR/inxi/inxi" # location of binary relative to repo submodule
else
    IXNI='./inxi/inxi' # location of binary relative to repo submodule
fi

# ixni surprisingly does not provide information on actual system-wide
# memory state, instead it provides the raw output from dmidecode which
# only shows information about the hardware as derived by the BIOS.
meminfo() {
    echo "Memory:" >&3
    free --human --total >&3
}

# when calling this, we redirect the output to FD 3 (as per logging)
sysinfo() {
    "$IXNI" -c 0 -v 4 >&3
    meminfo
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
