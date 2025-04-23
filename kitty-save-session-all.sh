#!/bin/bash
# Global Environment Variables:
#  KITTY_SESSION_SOCK_PATTERN - The pattern that includes '{kitty_pid}' that was used in the kitty 'listen_on' config directive, without the 'unix:' prefix.
#                               If this starts with '@' it will look for datagram sockets instead of sockets in a folder, and KITTY_SESSION_SOCKS_PATH is
#                               ignored. The '{kitty_pid}' placeholder must be part of the file name, not any directory path.
#                               If using '@', be sure the naming is unique so it can be differented among all system listening sockets!
#                               Default=${HOME}/.cache/kitty/sessions/{kitty_pid}.sock
#  KITTY_SESSION_SAVE_DIR - The folder to save the *.kitty session files in. Will be deleted and replaced every time the sessions are saved.
#  KITTY_SESSION_SAVE_OPTS - optional. If set it must be space separteed options that will be passed to the kitty-convert-dump.py script
#                            unquoted.
#  KITTY_SESSION_SOCKS_PATH - a deprecated option for setting a folder to find sockets named '{kitty_pid}.sock' in. Only used if KITTY_SESSION_SOCK_PATTERN
#                             is unset. Defaults to ${HOME}/.cache/kitty/sessions

set -o pipefail # make piped commands return exit codes like you'd expect

SCRIPT_DIR=$(dirname "$0")
readonly SCRIPT_DIR

[[ -f ${SCRIPT_DIR}/kitty-convert-dump.py ]] || { echo >&2 "Cannot find kitty-convert-dump.py in \$(dirname $0)=${SCRIPT_DIR}"; exit 1; }

#shellcheck disable=SC1091 # shellcheck can't follow includes
source "${SCRIPT_DIR}/kitty-save-session-common.incl" || { echo >&2 "Cannot source common.incl in \$(dirname $0)=${SCRIPT_DIR}"; exit 1; }

#------------------------------------------------

# Make sure the save directory exists
mkdir -p "$KITTY_SESSION_SAVE_DIR"

# will be either a list of fully pathed socket files in the my_active_sessions_folder, or a list of datagram sockets (starting with '@') matching the kitty format
active_session_sockets=()
# gets the list of sockets in active_session_sockets array
get_active_sockets active_session_sockets

# We don't want to clean up previous saved sessions if there aren't any active ones to save instead.
# So there's nothing else to do here
(( ${#active_session_sockets[@]} > 0 )) || quit "No active sessions, skipping saving and cleanup"

# get the list of active pids from the socket names
active_session_pids=()
readarray -t active_session_pids < <(get_pids_from_socket_names "${active_session_sockets[@]}")

# create a temporary directory to put the new sessions in
temp_dir=$(mktemp -d)

# always cleanup the temp folder on exit.  We either moved it somewhere else on success, or it needs to be cleaned up on failure.
trap 'rm -rf "${temp_dir}"' EXIT

echo "Generating saved sessions into temporary directory: ${temp_dir}"

any_sessions_saved=false
# Iterate thru the indexes of the active session sockets, querying the state, converting it, and writing it to a saved session file
# named after the kitty pid it came from.
for idx in "${!active_session_sockets[@]}"; do
    # the indexing matches between these two arrays
    active_socket="${active_session_sockets[$idx]}"
    active_pid="${active_session_pids[$idx]}"

    # name to write the converted session details to
    saved_session_name="${temp_dir}/$(get_saved_session_file_name_from_pid "${active_pid}")"

    # blank the file in case it already exists, and make sure we can actually write to it
    echo -n "" > "$saved_session_name" || die "Cannot write to saved session file: ${saved_session_name}"

    # pipe JSON output directly to the python convertor that turns it into a consumable session file.
    echo "kitty @ ls --to=\"unix:$active_socket\" | \"${SCRIPT_DIR}/kitty-convert-dump.py\" ${KITTY_SESSION_SAVE_OPTS:-} > \"$saved_session_name\""
    #shellcheck disable=SC2086 # intentional wordsplitting on KITTY_SESSION_SAVE_OPTS
    kitty @ ls --to="unix:$active_socket" | "${SCRIPT_DIR}/kitty-convert-dump.py" ${KITTY_SESSION_SAVE_OPTS:-} > "$saved_session_name"

    # Is the file not empty?
    if [[ -s "$saved_session_name" ]]; then
        any_sessions_saved=true
    else
        # file is empty or doesn't exist, so try each step one-by-one so output will reveal which part failed, possibly in the details
        # of what's output by one of the steps.
        echo >&2 "Failed to save to file: $saved_session_name"
        if ! is_dgram; then
            echo >&2 "Possibly broken socket file leftover from prior boot?: $active_socket"
        fi

        # print the output from each step so we can see what might have failed
        set -x
        # socket read error?
        kitty @ ls --to="unix:$active_socket" >&2
        # Parser error?
        #shellcheck disable=SC2086 # intentional wordsplitting on KITTY_SESSION_SAVE_OPTS
        kitty @ ls --to="unix:$active_socket" | "${SCRIPT_DIR}/kitty-convert-dump.py" ${KITTY_SESSION_SAVE_OPTS:-} >&2
        # File write error?
        echo -n "" >> "$saved_session_name" || echo >&2 "failed"
        set +x

        # If it's a non-datagram socket (a socket file), it could be a broken socket left over from a prior boot
        # if the socket folder is in persistent storage.  We can't tell, so just assume that's the case for non-dgram
        # sockets.  If it's a dgram socket however, there's something wrong with the setup, it should never fail.
        ! is_dgram || die
    fi
done

# If using socket files, any success is considered success since we may have broken socket files left over from a prior boot
# in persistent storage.
if ! ${any_sessions_saved} &>/dev/null; then
    echo >&2 "Failed to save any sessions to files"
    exit 1
fi

# Swap in the newly created directory for the old one as atomically as possible, then remove the old one
echo >&2 "Swapping the new saved sessions in ${temp_dir} for the old ones in ${KITTY_SESSION_SAVE_DIR}"
mv "${KITTY_SESSION_SAVE_DIR}" "${KITTY_SESSION_SAVE_DIR}.bak" \
    && mv "${temp_dir}"  "${KITTY_SESSION_SAVE_DIR}" \
    && rm -r "${KITTY_SESSION_SAVE_DIR}.bak"
ret=$?

if (( ret != 0 )); then
    # restore the old savedd sessions if we failed when trying to swap in the new ones.
    mv "${KITTY_SESSION_SAVE_DIR}.bak" "${KITTY_SESSION_SAVE_DIR}"
    echo >&2 "Failed to replace old saved sessions with new ones"
    exit 1
fi