#!/usr/bin/env bash
# Verifica os cards da Vercel usados no README e tenta recuperar os que cairem.
#
# Para cada card:
#   1. testa a URL (com cache-buster, para a Vercel realmente executar a funcao);
#   2. se falhar, tenta de novo com espera crescente (a "carregada");
#   3. na 2a falha, dispara o Deploy Hook da Vercel, se existir, e espera o redeploy;
#   4. se o card voltou depois de ter falhado, atualiza o &v= da URL no README,
#      para o proxy do GitHub (camo) descartar a copia de erro que guardou.
#
# Sai com codigo 1 se algum card nao se recuperou.
# Uso: check-cards.sh [caminho-do-README]
# Hooks (opcionais, via env): HOOK_STREAK, HOOK_ACTIVITY, HOOK_STATS

set -u

README="${1:-README.md}"
ATTEMPTS="${ATTEMPTS:-4}"
SLEEP_BASE="${SLEEP_BASE:-15}"
HOOK_WAIT="${HOOK_WAIT:-90}"

# Mensagens que os servicos devolvem (com HTTP 200!) quando falham.
ERROR_REGEX="Failed to retrieve|Can't fetch any contribution|Something went wrong|Could not fetch|Could not resolve|rate limit|Maximum retries|Missing params|Please check your username|Unknown error"

# chave|nome|regex que identifica a URL no README|variavel do hook
CARDS=(
  "streak|🔥 Streak Stats|streak-stats-dvgo|HOOK_STREAK"
  "activity|📈 Activity Graph|activity-graph-topaz-mu|HOOK_ACTIVITY"
  "stats|📊 GitHub Stats|eta-bay-80\.vercel\.app/api\?username|HOOK_STATS"
  "langs|💻 Top Languages|eta-bay-80\.vercel\.app/api/top-langs|HOOK_STATS"
)

# Retorna 0 se a URL devolve um SVG valido e sem mensagem de erro.
check_url() {
  local url="$1" tmp status
  tmp="$(mktemp)"
  status="$(curl -sL -m 40 -o "$tmp" -w "%{http_code}" "${url}&_check=$(date +%s)" || echo 000)"
  LAST_STATUS="$status"
  if [ "$status" = "200" ] \
    && [ "$(wc -c < "$tmp")" -ge 300 ] \
    && grep -q "<svg" "$tmp" \
    && ! grep -qiE "$ERROR_REGEX" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Atualiza (ou cria) o &v=<timestamp> nas linhas do README que casam com o regex.
bump_version() {
  local re="$1" ts
  ts="$(date +%s)"
  sed -i.bak -E "\\#$re#{s/&v=[0-9]+//;s/(https:\/\/[^\"]*)\"/\1\&v=${ts}\"/;}" "$README"
  rm -f "$README.bak"
}

failed=0

for entry in "${CARDS[@]}"; do
  IFS='|' read -r key name re hookvar <<< "$entry"

  url="$(grep -oE 'https://[^"]+' "$README" | grep -E "$re" | head -1 | sed 's/í/%C3%AD/g')"
  if [ -z "$url" ]; then
    echo "::warning::$name: URL nao encontrada no README, ignorado."
    continue
  fi

  hook="${!hookvar:-}"
  had_problem=0
  hook_used=0
  ok=0

  for attempt in $(seq 1 "$ATTEMPTS"); do
    if check_url "$url"; then
      ok=1
      break
    fi

    had_problem=1
    echo "  $name: tentativa $attempt/$ATTEMPTS falhou (HTTP $LAST_STATUS)"

    if [ "$attempt" -ge 2 ] && [ -n "$hook" ] && [ "$hook_used" = "0" ]; then
      hook_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$hook" || echo 000)"
      hook_used=1
      echo "  $name: redeploy solicitado na Vercel (HTTP $hook_status), aguardando ${HOOK_WAIT}s"
      sleep "$HOOK_WAIT"
    else
      sleep $((attempt * SLEEP_BASE))
    fi
  done

  if [ "$ok" = "1" ] && [ "$had_problem" = "0" ]; then
    echo "✅ $name: OK"
  elif [ "$ok" = "1" ]; then
    echo "♻️  $name: estava com problema e voltou, atualizando cache no README"
    bump_version "$re"
  else
    if [ -z "$hook" ]; then
      echo "::error::$name continua fora do ar. Configure o secret ${hookvar/HOOK_/VERCEL_}_HOOK para o redeploy automatico. URL: $url"
    else
      echo "::error::$name continua fora do ar mesmo apos o redeploy. URL: $url"
    fi
    failed=1
  fi
done

exit "$failed"
