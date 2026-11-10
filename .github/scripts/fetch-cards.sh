#!/usr/bin/env bash
# Baixa os cards do perfil, valida que sao SVGs "de verdade" (e nao SVGs de erro)
# e so entao sobrescreve o arquivo. Se todas as fontes falharem, mantem a versao anterior.
#
# Uso: fetch-cards.sh <diretorio-de-saida>

set -u

OUT="${1:?informe o diretorio de saida}"
USER_NAME="NicoleOG12"
ATTEMPTS=3

mkdir -p "$OUT"

# Mensagens que os servicos devolvem (com HTTP 200!) quando falham.
ERROR_REGEX="Failed to retrieve|Can't fetch any contribution|Something went wrong|Could not fetch|Could not resolve|rate limit|Maximum retries|Missing params|Please check your username|Unknown error"

STREAK_QS="theme=radical&hide_border=true&border_radius=20&ring=FF1493&fire=FF1493&currStreakLabel=FF1493&sideLabels=FF69B4&dates=FFFFFF&currStreakNum=FFFFFF&sideNums=FFFFFF&background=0D1117"
ACTIVITY_QS="theme=github-compact&hide_border=true&bg_color=0D1117&color=FF1493&line=FF1493&point=FF69B4&area=true&area_color=FF1493"
STATS_QS="show_icons=true&count_private=true&include_all_commits=true&hide_border=true&border_radius=20&rank_icon=github&custom_title=Estat%C3%ADsticas%20do%20GitHub&title_color=FF1493&icon_color=FF69B4&text_color=FFFFFF&bg_color=0D1117&card_width=500"
LANGS_QS="layout=compact&langs_count=8&hide=svg,markdown&hide_border=true&border_radius=20&title_color=FF1493&text_color=FFFFFF&bg_color=0D1117&card_width=500"

# nome do arquivo | URLs em ordem de preferencia (separadas por espaco)
# A primeira e o seu deploy na Vercel; as demais sao instancias publicas de reserva.
CARDS=(
  "streak.svg|https://github-readme-streak-stats-dvgo.vercel.app/?user=${USER_NAME}&${STREAK_QS} https://streak-stats.demolab.com/?user=${USER_NAME}&${STREAK_QS}"
  "activity.svg|https://github-readme-activity-graph-topaz-mu.vercel.app/graph?username=${USER_NAME}&${ACTIVITY_QS} https://github-readme-activity-graph.vercel.app/graph?username=${USER_NAME}&${ACTIVITY_QS}"
  "stats.svg|https://github-readme-stats-eta-bay-80.vercel.app/api?username=${USER_NAME}&${STATS_QS} https://github-readme-stats.vercel.app/api?username=${USER_NAME}&${STATS_QS}"
  "top-langs.svg|https://github-readme-stats-eta-bay-80.vercel.app/api/top-langs/?username=${USER_NAME}&${LANGS_QS} https://github-readme-stats.vercel.app/api/top-langs/?username=${USER_NAME}&${LANGS_QS}"
)

# Retorna 0 se o arquivo e um SVG valido e sem mensagem de erro.
is_valid_svg() {
  local file="$1"
  [ -s "$file" ] || return 1
  [ "$(wc -c < "$file")" -ge 300 ] || return 1
  grep -q "<svg" "$file" || return 1
  if grep -qiE "$ERROR_REGEX" "$file"; then
    return 1
  fi
  return 0
}

failed=0

for entry in "${CARDS[@]}"; do
  name="${entry%%|*}"
  urls="${entry#*|}"
  tmp="$(mktemp)"
  ok=0

  for url in $urls; do
    host="$(echo "$url" | awk -F/ '{print $3}')"
    for attempt in $(seq 1 "$ATTEMPTS"); do
      status="$(curl -sL -m 40 -o "$tmp" -w "%{http_code}" "$url" || echo 000)"
      if [ "$status" = "200" ] && is_valid_svg "$tmp"; then
        ok=1
        break 2
      fi
      echo "  [$name] $host tentativa $attempt/$ATTEMPTS falhou (HTTP $status)"
      sleep $((attempt * 5))
    done
  done

  if [ "$ok" = "1" ]; then
    mv "$tmp" "$OUT/$name"
    echo "OK    $name atualizado (fonte: $host)"
  elif [ -s "$OUT/$name" ]; then
    rm -f "$tmp"
    echo "::warning::$name: todas as fontes falharam, mantida a versao anterior."
  else
    rm -f "$tmp"
    echo "::error::$name: todas as fontes falharam e nao ha versao anterior."
    failed=1
  fi
done

exit "$failed"
