#!/bin/bash
set -o pipefail

# This must match KITTY_SESSION_SAVE_DIR when kitty-save-session-all.sh was called
my_saved_sessions_folder=${KITTY_SESSION_SAVE_DIR:-${HOME}/.cache/kitty/saved-sessions}

mkdir -p "$my_saved_sessions_folder"

saved_session_file=()
readarray -t saved_active_session_files < <(find "$my_saved_sessions_folder" -mindepth 1 -name '*.kitty')

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