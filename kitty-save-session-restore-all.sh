#!/bin/bash
# Global Environment Variables:
#  KITTY_SESSION_SAVE_DIR - The folder to save the *.kitty session files in.

set -o pipefail

SCRIPT_DIR=$(dirname "$0")
readonly SCRIPT_DIR

#shellcheck disable=SC1091 # shellcheck can't follow includes
source "${SCRIPT_DIR}/kitty-save-session-common.incl" || { echo >&2 "Cannot source common.incl in \$(dirname $0)=${SCRIPT_DIR}"; exit 1; }

# Make sure the save directory exists, even if we don't end up doing anything because it's empty
mkdir -p "$KITTY_SESSION_SAVE_DIR"

saved_session_file=()
readarray -t saved_session_file < <(get_saved_sessions)

for saved in "${saved_session_file[@]}"; do
    # --detach causes it to run in the background, but completely detached from this calling session,
    # allowing this shell session to exit normally without killing the kitty instances it created, or
    # getting stuck thinking it needs to wait on child processes to exit.
    set -x
    kitty --detach --session="$saved"
    set +x
done

# The existing saved session file names will no longer match the sockets since new pids are assigned on
# creation, but next time we run kitty-session-save-all.sh these will all get cleaned up and new copies
# with the new pids will be created.