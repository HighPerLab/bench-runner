##
## This module provides some miscellaneous functions
##

pushd() {
    command pushd "$@" >/dev/null
}

popd() {
    command pushd "$@" >/dev/null
}

mounttmp() {
    # sanity check
    if [ -f "/tmp/.mount" ]; then
        inf "already mounted, continuing"
    else
        if ! mount /tmp; then
            error "unable to mount /tmp"
            exit 10
        fi
        touch /tmp/.mount
        inf "mounted /tmp"
    fi
}

umounttmp() {
    # sanity check
    if [ -f "/tmp/.mount" ]; then
        if ! umount /tmp; then
            error "unable to un-mount /tmp"
            exit 10
        fi
    else
        warn "not working in a mounted FS, ignoring..."
    fi
}
