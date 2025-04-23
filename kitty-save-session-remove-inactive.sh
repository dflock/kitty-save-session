#!/bin/bash
# Global Environment Variables:
#  KITTY_SESSION_SOCK_PATTERN - The pattern that includes '{kitty_pid}' that was used in the kitty 'listen_on' config directive, without the 'unix:' prefix.
#                               If this starts with '@' it will look for datagram sockets instead of sockets in a folder, and KITTY_SESSION_SOCKS_PATH is
#                               ignored. The '{kitty_pid}' placeholder must be part of the file name, not any directory path.
#                               If using '@', be sure the naming is unique so it can be differented among all system listening sockets!
#                               Default=${HOME}/.cache/kitty/sessions/{kitty_pid}.sock
#  KITTY_SESSION_SAVE_DIR - The folder to save the *.kitty session files in.
#  KITTY_SESSION_SAVE_OPTS - optional. If set it must be space separteed options that will be passed to the kitty-convert-dump.py script
#                            unquoted.
#  KITTY_SESSION_SOCKS_PATH - a deprecated option for setting a folder to find sockets named '{kitty_pid}.sock' in. Only used if KITTY_SESSION_SOCK_PATTERN
#                             is unset. Defaults to ${HOME}/.cache/kitty/sessions
set -o pipefail # make piped commands return exit codes like you'd expect

SCRIPT_DIR=$(dirname "$0")
readonly SCRIPT_DIR

#shellcheck disable=SC1091 # shellcheck can't follow includes
source "${SCRIPT_DIR}/kitty-save-session-common.incl" || { echo >&2 "Cannot source common.incl in \$(dirname $0)=${SCRIPT_DIR}"; exit 1; }

#------------------------------------------------

# Make sure the save directory exists, even if we don't end up doing anything because it's empty
mkdir -p "$KITTY_SESSION_SAVE_DIR"

active_session_sockets=()
# get the socket list
get_active_sockets active_session_sockets
# get the list of active pids from the socket names
active_session_pids=()
if (( ${#active_session_sockets[@]} > 0 )); then
    readarray -t active_session_pids < <(get_pids_from_socket_names "${active_session_sockets[@]}")
fi

saved_session_file=()
readarray -t saved_session_file < <(get_saved_sessions)

# this is such a common case, watch for it and skip the searching for matches
if (( ${#active_session_pids[@]} > 0 )); then
    # Remove files from the saved_session_file list that still have active sessions.
    for saved_idx in "${!saved_session_file[@]}"; do
        for active_pid in "${active_session_pids[@]}"; do
            # strips the .kitty extension and path from the file name
            saved_pid=$(get_pid_from_saved_session "${saved_session_file[$saved_idx]}")
            if [[ "$saved_pid" == "$active_pid" ]]; then
                # remove it from our list, it matches an active pid
                unset "saved_session_file[$saved_idx]"
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