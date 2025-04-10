#!/bin/bash
# Global Environment Variables:
#  KITTY_SESSION_SOCKS_PATH - The folder to find the kitty remote control *.sock files in.
#  KITTY_SESSION_SAVE_DIR - The folder to save the *.kitty session files in.
#  KITTY_SESSION_SAVE_OPTS - optional. If set it must be space separteed options that will be passed to the kitty-convert-dump.py script
#                            unquoted.

set -o pipefail # make piped commands return exit codes like you'd expect

SCRIPT_DIR=$(dirname "$0")
readonly SCRIPT_DIR

[[ -f ${SCRIPT_DIR}/kitty-convert-dump.py ]] || { echo >&2 "Cannot find kitty-convert-dump.py in \$(dirname $0)=${SCRIPT_DIR}"; exit 1; }

# TODO: Make this more atomic by creating a copy of the saved session folder to cleanup and populate, then swap out the whole folder

# this must match kitty.conf's 'listen_on unix:${KITTY_SESSION_SOCKS_PATH}/{kitty_pid}.sock', 
# and you must also have 'allow_remote_control' set to 'on', 'socket', or 'socket-only'
my_active_sessions_folder=${KITTY_SESSION_SOCKS_PATH:-${HOME}/.cache/kitty/sessions}

mkdir -p "$my_active_sessions_folder"

# Folder to save your sessions in. Not recommended to be the same as my_active_sessions_folder
my_saved_sessions_folder=${KITTY_SESSION_SAVE_DIR:-${HOME}/.cache/kitty/saved-sessions}

mkdir -p "$my_saved_sessions_folder"

active_session_files=()
readarray -t active_session_files < <(find "$my_active_sessions_folder" -mindepth 1 -name '*.sock')

# We don't want to clean up previous saved sessions if there aren't any active ones to save instead.
# So there's nothing else to do here
(( ${#active_session_files[@]} > 0 )) || { echo "No active sessions, skipping saving and cleanup"; exit 0; }

saved_session_file=()
readarray -t saved_session_file < <(find "$my_saved_sessions_folder" -mindepth 1 -name '*.kitty')

# Remove files from the saved_session_file list that still have active sessions.
for saved_idx in "${!saved_session_file[@]}"; do
    for active in "${active_session_files[@]}"; do
        # strips the .kitty extension and path from the file name
        saved_pid=$(basename -s .kitty "${saved_session_file[$saved_idx]}")
        # strips the .sock extension and path from the file name
        active_pid=$(basename -s .sock "$active")
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

any_sessions_saved=false
# now iterate thru and save session states, overwriting state files if we need to
for active in "${active_session_files[@]}"; do
    # sock file name without extension or path, add saved session path and .kitty extension
    saved_session_name=${my_saved_sessions_folder}/$(basename -s .sock "$active").kitty

    # blank the file
    echo -n "" > "$saved_session_name" || { echo >&2 "Cannot write to saved session file: ${saved_session_name}"; exit 1; }

    # pipe JSON output directly to the python convertor that turns it into a consumable session file.
    echo "kitty @ ls --to=\"unix:$active\" | \"${SCRIPT_DIR}/kitty-convert-dump.py\" ${KITTY_SESSION_SAVE_OPTS:-} > \"$saved_session_name\""
    set -x
    kitty @ ls --to="unix:$active" | "${SCRIPT_DIR}/kitty-convert-dump.py" ${KITTY_SESSION_SAVE_OPTS:-} > "$saved_session_name"
    set +x

    # Is the file not empty?
    if [[ -s "$saved_session_name" ]]; then
        any_sessions_saved=true
    else
        echo >&2 "Failed to save to file: $saved_session_name"
        # print the output from each step so we can see what might have failed
        set -x
        kitty @ ls --to="unix:$active"
        kitty @ ls --to="unix:$active" | "${SCRIPT_DIR}/kitty-convert-dump.py" ${KITTY_SESSION_SAVE_OPTS:-}
        echo -n "" >> "$saved_session_name" || echo "failed"
        set +x
    fi
done

if ! ${any_sessions_saved} &>/dev/null; then
    echo >&2 "Failed to save any sessions to files"
    exit 1
fi

# saved_session_file now only contains sessions that don't match active pids, so remove them
set -x
rm -f "${saved_session_file[@]}"
ret=$?
set +x

if (( ret != 0 )); then
    echo >&2 "Failed to cleanup inactive saved sessions"
    exit 1
fi