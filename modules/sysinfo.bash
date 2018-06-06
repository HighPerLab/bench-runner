##
## This module provides functions to get basic system information.
##
##   We make use of ixni primarily.
##

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
