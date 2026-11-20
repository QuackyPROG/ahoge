# When push-to-phone.sh installs and re-signs. Sourced by push-to-phone.sh and Scripts/test-push-to-phone.sh; no side effects.
# A quiet window is HH-HH in local hours, start inclusive, end exclusive; 22-06 wraps midnight.

resign_after=$((3 * 24 * 60 * 60))
# Outside the window, re-sign only when less than a day of the free Apple ID's 7 days is left.
resign_urgent_after=$((6 * 24 * 60 * 60))

quiet_hours_valid() { # window
  [[ "$1" =~ ^([01][0-9]|2[0-3])-([01][0-9]|2[0-3])$ ]] && [ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[2]}" ]
}

in_quiet_window() { # window, hour
  local start=$((10#${1%-*})) end=$((10#${1#*-})) hour=$((10#$2))
  if [ "$start" -le "$end" ]; then
    [ "$hour" -ge "$start" ] && [ "$hour" -lt "$end" ]
  else
    [ "$hour" -ge "$start" ] || [ "$hour" -lt "$end" ]
  fi
}

should_install() { # window, hour, force (true|false)
  [ "$3" = true ] || in_quiet_window "$1" "$2"
}

should_resign() { # window, hour, signature age in seconds
  if in_quiet_window "$1" "$2"; then
    [ "$3" -ge "$resign_after" ]
  else
    [ "$3" -ge "$resign_urgent_after" ]
  fi
}
