#!/bin/bash
input=$(cat)

DETAIL=cached

IFS=$'\t' read -r MODEL SIZE TOTAL PCT FRESH CREAD CWRITE F5 F5R D7 D7R <<< "$(
  echo "$input" | jq -r '
    [ (.model.display_name // "?"),
      (.context_window.context_window_size // 200000),
      (.context_window.total_input_tokens // 0),
      (.context_window.used_percentage // 0 | floor),
      (.context_window.current_usage.input_tokens // 0),
      (.context_window.current_usage.cache_read_input_tokens // 0),
      (.context_window.current_usage.cache_creation_input_tokens // 0),
      (.rate_limits.five_hour.used_percentage // "x"),
      (.rate_limits.five_hour.resets_at // "x"),
      (.rate_limits.seven_day.used_percentage // "x"),
      (.rate_limits.seven_day.resets_at // "x")
    ] | @tsv')"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'; C='\033[36m'; N='\033[0m'
VS=$'\uFE0E'

fmt() {
  local n=${1:-0}
  if   [ "$n" -ge 1000000 ]; then printf '%d.%01dM' $((n/1000000)) $((n%1000000/100000))
  elif [ "$n" -ge 1000 ];    then printf '%d.%01dk' $((n/1000))    $((n%1000/100))
  else printf '%d' "$n"; fi
}

color() {
  if   [ "$1" -ge 90 ]; then printf '%b' "$R"
  elif [ "$1" -ge 70 ]; then printf '%b' "$Y"
  else printf '%b' "$G"; fi
}

countdown() {
  [ "$1" = "x" ] && return
  local diff=$(( $1 - $(date +%s) ))
  [ "$diff" -lt 0 ] && diff=0
  local d=$((diff/86400)) h=$((diff%86400/3600)) m=$((diff%3600/60))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

FILLED=$((PCT/10))
[ "$PCT" -ge 95 ] && FILLED=10
EMPTY=$((10-FILLED))
printf -v A "%${FILLED}s"; printf -v B "%${EMPTY}s"
BAR="${A// /▓}${B// /░}"
CC=$(color "$PCT")

LEFT="${C}[$MODEL]${N} ${CC}${BAR} ${PCT}%${N}  $(fmt "$TOTAL")${D}/$(fmt "$SIZE")${N}"

COLS=${COLUMNS:-120}
if [ "$COLS" -ge 100 ]; then
  if [ "$DETAIL" = cached ] && [ "$TOTAL" -gt 0 ]; then
    LEFT="$LEFT  ${D}·  $(( CREAD * 100 / TOTAL ))% cached${N}"
  elif [ "$DETAIL" = split ]; then
    LEFT="$LEFT  ${D}·${N}  ↑ $(fmt "$FRESH")   ${D}↺ $(fmt "$CREAD")   ✎${VS} $(fmt "$CWRITE")${N}"
  fi
fi

RIGHT=""
if [ "$F5" != "x" ]; then
  P=$(printf '%.0f' "$F5"); RIGHT="$(color "$P")5h ${P}%${N}"
  T=$(countdown "$F5R"); [ -n "$T" ] && RIGHT="$RIGHT ${D}${T}${N}"
fi
if [ "$D7" != "x" ]; then
  P=$(printf '%.0f' "$D7"); S="$(color "$P")7d ${P}%${N}"
  T=$(countdown "$D7R"); [ -n "$T" ] && S="$S ${D}${T}${N}"
  RIGHT="${RIGHT:+$RIGHT  ${D}·${N}  }$S"
fi

[ -n "$RIGHT" ] && printf '%b\n' "$LEFT  ${D}│${N}  $RIGHT" || printf '%b\n' "$LEFT"
