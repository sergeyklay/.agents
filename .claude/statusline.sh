#!/bin/sh
input=$(cat)

DETAIL=cached

tab=$(printf '\t')
IFS=$tab read -r MODEL SIZE TOTAL PCT FRESH CREAD CWRITE F5 F5R D7 D7R <<EOF
$(printf '%s\n' "$input" | jq -r '
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
    ] | @tsv')
EOF

G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'; C='\033[36m'; N='\033[0m'
VS=$(printf '\357\270\216')

fmt() {
  n=${1:-0}
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
  reset_at=$1
  now=$(date +%s)
  diff=$((reset_at - now))
  [ "$diff" -lt 0 ] && diff=0
  d=$((diff/86400))
  h=$((diff%86400/3600))
  m=$((diff%3600/60))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

make_bar() {
  filled=$1
  empty=$2
  while [ "$filled" -gt 0 ]; do
    printf '%s' '▓'
    filled=$((filled - 1))
  done
  while [ "$empty" -gt 0 ]; do
    printf '%s' '░'
    empty=$((empty - 1))
  done
}

FILLED=$((PCT/10))
[ "$PCT" -ge 95 ] && FILLED=10
EMPTY=$((10-FILLED))
BAR=$(make_bar "$FILLED" "$EMPTY")
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
