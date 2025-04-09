#!/bin/bash
set -o pipefail # make piped commands return exit codes like you'd expect

# this must match kitty.conf's 'listen_on unix:${KITTY_SESSION_SOCKS_PATH}/{kitty_pid}.sock', 
# and you must also have 'allow_remote_control' set to 'on', 'socket', or 'socket-only'
my_active_sessions_folder=${KITTY_SESSION_SOCKS_PATH:-${HOME}/.cache/kitty/sessions}

mkdir -p "$my_active_sessions_folder"

# Folder to save your sessions in. Not recommended to be the same as my_active_sessions_folder
my_saved_sessions_folder=${KITTY_SESSION_SAVE_DIR:-${HOME}/.cache/kitty/saved-sessions}

mkdir -p "$my_saved_sessions_folder"

active_session_files=()
readarray -t active_session_files < <(find "$my_active_sessions_folder" -mindepth 1 -name '*.sock')

saved_session_file=()
readarray -t saved_active_session_files < <(find "$my_saved_sessions_folder" -mindepth 1 -name '*.kitty')

# this is such a common case, watch for it and skip the searching for matches
if (( ${#active_session_files[@]} > 0 )); then
    # Remove files from the saved_session_file list that still have active sessions.
    for saved_idx in "${!saved_session_file[@]}"; do
        for active in "${active_session_files[@]}"; do
            # strips the .kitty extension and path from the file name
            saved_pid=$(basename -s .kitty "${saved_session_file[$saved_idx]}")
            # strips the .sock extension and path from the file name
            active_pid=$(basename -s .kitty "$active")
            if [[ "$saved_pid" == "$active_pid" ]]; then
                # remove it from our list, it matches an active pid
                unset saved_session_file[$saved_idx]
                # found a match, stop looking for more active sessions to match this saved session pid
                break
            fi
        done
    done
    # saved_session_file is now a list of saved session files that don't match any active sessions.
fi

# saved_session_file now only contains sessions that don't match active pids, so remove them
set -x
rm -f "${saved_session_file[@]}"
ret=$?
set +x

exit $ret