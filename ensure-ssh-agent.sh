#!/usr/bin/env sh
SSH_AGENT_SOCKET="${SSH_AGENT_SOCKET:-$HOME/.ssh/agent.sock}"
SSH_AGENT_KEY="${SSH_AGENT_KEY:-$HOME/.ssh/id_ed25519}"

export SSH_AUTH_SOCK="$SSH_AGENT_SOCKET"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Check whether the configured agent is reachable.
ssh-add -l >/dev/null 2>&1
agent_status=$?

case "$agent_status" in
    0)
        # Agent is reachable and already has at least one key.
        ;;
    1)
        # Agent is reachable but currently has no keys.
        ;;
    2)
        # Agent is unreachable. Remove a stale socket and start a new agent.
        rm -f "$SSH_AUTH_SOCK"

        agent_output="$(ssh-agent -a "$SSH_AUTH_SOCK" -s 2>/dev/null)" || {
            printf '%s\n' "Failed to start ssh-agent on $SSH_AUTH_SOCK" >&2
            return 1 2>/dev/null || exit 1
        }

        eval "$agent_output" >/dev/null
        ;;
    *)
        printf '%s\n' "Unexpected ssh-add exit status: $agent_status" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

# Only prompt for a key passphrase in an interactive shell.
case "$-" in
    *i*)
        if [ -f "$SSH_AGENT_KEY" ]; then
            public_key="${SSH_AGENT_KEY}.pub"

            # Prefer fingerprint comparison when the public key exists.
            if [ -f "$public_key" ]; then
                key_fingerprint="$(
                    ssh-keygen -lf "$public_key" 2>/dev/null |
                    awk 'NR == 1 { print $2 }'
                )"

                if [ -n "$key_fingerprint" ]; then
                    if ! ssh-add -l 2>/dev/null |
                        awk '{ print $2 }' |
                        grep -Fxq "$key_fingerprint"
                    then
                        ssh-add "$SSH_AGENT_KEY"
                    fi
                fi
            else
                # Fall back to loading the key when no public key file exists
                # and the agent currently has no identities.
                ssh-add -l >/dev/null 2>&1
                if [ "$?" -eq 1 ]; then
                    ssh-add "$SSH_AGENT_KEY"
                fi
            fi
        fi
        ;;
esac
