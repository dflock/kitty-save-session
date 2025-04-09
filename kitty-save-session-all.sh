#!/bin/bash
set -o pipefail # make piped commands return exit codes like you'd expect

# TODO: Make this more atomic by creating a copy of the saved session folder to cleanup and populate, then swap out the whole folder

# this must match kitty.conf's 'listen_on unix:${KITTY_SESSION_SOCKETS_PATH}/{kitty_pid}.sock', 
# and you must also have 'allow_remote_control' set to 'on', 'socket', or 'socket-only'
my_active_sessions_folder=${KITTY_SESSION_SOCKETS_PATH:-${HOME}/.cache/kitty/sessions}

mkdir -p "$my_active_sessions_folder"

# Folder to save your sessions in. Not recommended to be the same as my_active_sessions_folder
my_saved_sessions_folder=${KITTY_SESSION_SAVED_STATE_PATH:-${HOME}/.cache/kitty/saved-sessions}

mkdir -p "$my_saved_sessions_folder"

active_session_files=()
readarray -t active_session_files < <(find $my_active_sessions_folder -mindepth 1 -name '*.sock')

# We don't want to clean up previous saved sessions if there aren't any active ones to save instead.
# So there's nothing else to do here
(( ${#active_session_files[@]} > 0 )) || exit 0

saved_session_file=()
readarray -t saved_active_session_files < <(find $my_saved_sessions_folder -mindepth 1 -name '*.kitty')

# Remove files from the saved_session_file list that still have active sessions.
for saved_idx in "${!saved_session_file[@]}"; do
    for active in "${active_session_files[@]}"; do
        # strips the .kitty extension and path from the file name
        saved_pid=$(basename -S .kitty ${saved_session_file[$saved_idx]})
        # strips the .sock extension and path from the file name
        active_pid=$(basename -S .kitty $active)
        if [[ "$saved_pid" == "$active_pid" ]]; then
            # remove it from our list, it matches an active pid
            unset saved_session_file[$saved_idx]
            # found a match, stop looking for more active sessions to match this saved session pid
            break
        fi
    done
done
# saved_session_file is now a list of saved session files that don't match any active sessions.
# We will remove them, but wait until we've created the new sessions first so an interruption or
# power loss won't lose all saved sessions entirely.

# now iterate thru and save session states, overwriting state files if we need to
for active in "${active_session_files[@]}"; do
    # sock file name without extension or path, add saved session path and .kitty extension
    saved_session_name=${my_saved_sessions_folder}/$(basename -S .sock $active).kitty

    # pipe JSON output directly to the python convertor that turns it into a consumable session file.
    kitty @ ls --to=unix:$active | python3 kitty-convert-dump.py > $saved_session_name
done

# saved_session_file now only contains sessions that don't match active pids, so remove them
rm -f "${saved_session_file[@]}"