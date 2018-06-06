##
## This module provides some miscellaneous functions
##

pushd() {
    command pushd "$@" >/dev/null
}

popd() {
    command pushd "$@" >/dev/null
}
