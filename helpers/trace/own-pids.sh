# shellcheck shell=bash
# ==============================================================================
# own-pids.sh - Sourced: own_pids, this run's processes by name
# ==============================================================================
# own_pids <ancestor> <name>...: the pids (one line, space-separated) of the processes
# whose command name is one of <name> (as `pgrep -x` matches it) and that descend from
# <ancestor>; fails when there is none. A process found by its name alone can be another
# checkout's or service instance's on the same machine: generate-reach-map.sh's SIGUSR2,
# sent to every `immich` there, killed other agents' servers as they started (exit 140).
own_pids() {
  local ancestor=$1 pid ppid comm cur hops found=()
  shift
  local -A parent=() name=()
  while read -r pid ppid comm; do
    parent[$pid]=$ppid
    name[$pid]=${comm##*/}
  done < <(ps -A -o pid= -o ppid= -o comm=)
  for pid in "${!parent[@]}"; do
    [[ " $* " == *" ${name[$pid]} "* ]] || continue
    cur=$pid hops=0
    while [ -n "${parent[$cur]:-}" ] && [ "$cur" -gt 1 ] && [ "$hops" -lt 64 ]; do
      cur=${parent[$cur]} hops=$((hops + 1))
      if [ "$cur" = "$ancestor" ]; then
        found+=("$pid")
        break
      fi
    done
  done
  [ ${#found[@]} -gt 0 ] || return 1
  echo "${found[@]}"
}
