#!/bin/sh
set -eu

env_file="${KAMAL_ENV_FILE:-.env.kamal.local}"
host_ssh_config="${HOST_SSH_CONFIG_FILE:-/tmp/fizzy-host-ssh-config}"
ssh_dir="${HOME}/.ssh"
ssh_config="${ssh_dir}/config"
known_hosts="${ssh_dir}/known_hosts"
start_marker="# BEGIN fizzy kamal devcontainer"
end_marker="# END fizzy kamal devcontainer"

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
touch "$ssh_config" "$known_hosts"
chmod 600 "$ssh_config" "$known_hosts"

base_config="$(mktemp)"
if [ -f "$host_ssh_config" ]; then
  cp "$host_ssh_config" "$base_config"
else
  cp "$ssh_config" "$base_config"
fi

if [ ! -f "$env_file" ]; then
  mv "$base_config" "$ssh_config"
  chmod 600 "$ssh_config"
  exit 0
fi

env_value() {
  sed -n "s/^$1=//p" "$env_file" | tail -n 1
}

kamal_server_alias="${KAMAL_SERVER_ALIAS:-$(env_value KAMAL_SERVER_ALIAS)}"
kamal_known_host="${KAMAL_KNOWN_HOST:-$(env_value KAMAL_KNOWN_HOST)}"
kamal_ssh_user="${KAMAL_SSH_USER:-$(env_value KAMAL_SSH_USER)}"

if [ -z "$kamal_server_alias" ] || [ -z "$kamal_known_host" ]; then
  mv "$base_config" "$ssh_config"
  chmod 600 "$ssh_config"
  exit 0
fi

clean_config="$(mktemp)"
awk -v start="$start_marker" -v end="$end_marker" '
  $0 == start { skip = 1; next }
  $0 == end { skip = 0; next }
  !skip { print }
' "$base_config" > "$clean_config"

tmp_config="$(mktemp)"
{
  printf '%s\n' "$start_marker"
  printf 'Host %s\n' "$kamal_server_alias"
  printf '  HostName %s\n' "$kamal_known_host"
  [ -z "$kamal_ssh_user" ] || printf '  User %s\n' "$kamal_ssh_user"
  printf '  ForwardAgent yes\n'
  printf '  IdentitiesOnly no\n'
  printf '  HostKeyAlias %s\n' "$kamal_known_host"
  printf '%s\n' "$end_marker"
  printf '\n'
  cat "$clean_config"
} > "$tmp_config"

mv "$tmp_config" "$ssh_config"
chmod 600 "$ssh_config"
rm -f "$base_config" "$clean_config"

if command -v ssh-keyscan >/dev/null 2>&1; then
  ssh-keygen -R "$kamal_known_host" -f "$known_hosts" >/dev/null 2>&1 || true
  ssh-keyscan -H "$kamal_known_host" >> "$known_hosts" 2>/dev/null || true
fi
