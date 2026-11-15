#!/usr/bin/env bash
# Axel-Reels на бункере: API внутри туннеля WireGuard (10.77.0.1:8090), своя база и свои секреты.
# Запуск на бункере:  curl -fsSL "kovcheg-systems.ru/ax.sh?1" | bash -s -- ФРАЗА
# ФРАЗА (не короче 16 знаков, латиница/цифры/дефисы) нужна, чтобы воркер на домашнем ПК получил тот же ключ.
# Повторный запуск безопасен: секреты и база сохраняются, сервис обновляется.
set -euo pipefail

ENVF=/etc/kovcheg-axel.env
DATA=/var/lib/kovcheg-axel
BUN=10.77.0.1
DOMAIN="${2:-axel.doroga-bunker.ru}"

find_deploy_dir() {
  local d
  d="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' deploy-gateway-1 2>/dev/null || true)"
  if [ -z "$d" ] || [ ! -f "$d/docker-compose.bunker.yml" ]; then
    d="$(dirname "$(find / -maxdepth 5 -name docker-compose.bunker.yml -path '*server/deploy*' 2>/dev/null | head -1)")"
  fi
  echo "$d"
}
rand() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40; }

main() {
  local pass="${1:-}"
  if [ "$(id -u)" != "0" ]; then echo "Нужен root."; exit 1; fi
  if [ "${#pass}" -lt 16 ]; then echo "Нужна фраза не короче 16 знаков: bash -s -- ВАША-ФРАЗА"; exit 1; fi
  local token; token="$(printf 'axel-worker:%s' "$pass" | sha256sum | cut -d' ' -f1)"

  local dir repo; dir="$(find_deploy_dir)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "Не нашёл папку шлюза на бункере."; exit 1; fi
  repo="$(git -C "$dir" rev-parse --show-toplevel)"

  echo ">> Получаю свежую версию из репозитория"
  git -C "$repo" fetch -q origin server-stable
  git -C "$repo" merge -q --ff-only FETCH_HEAD
  local axel="$repo/axel-reels"
  if [ ! -f "$axel/deploy/docker-compose.bunker.yml" ]; then echo "В репозитории ещё нет axel-reels (ветка server-stable)."; exit 1; fi

  echo ">> Настройки"
  umask 077
  if [ ! -f "$ENVF" ]; then
    cp "$axel/deploy/.env.example" "$ENVF"
    sed -i "s|^AXEL_ADMIN_TOKEN=.*|AXEL_ADMIN_TOKEN=$(rand)|" "$ENVF"
  fi
  sed -i "s|^AXEL_WORKER_TOKEN=.*|AXEL_WORKER_TOKEN=$token|" "$ENVF"
  sed -i "s|^AXEL_PUBLIC_URL=.*|AXEL_PUBLIC_URL=https://$DOMAIN|" "$ENVF"
  chmod 600 "$ENVF"
  mkdir -p "$DATA"; chown 10001 "$DATA"

  echo ">> Собираю и запускаю (первый раз 1-3 минуты)"
  docker compose -f "$axel/deploy/docker-compose.bunker.yml" up -d --build --remove-orphans </dev/null

  echo "10 4 * * * root bash $axel/deploy/backup.sh >/dev/null 2>&1" > /etc/cron.d/axel-backup

  local ok=""
  for _ in $(seq 1 24); do
    ok="$(curl -fsS -m 4 "http://$BUN:8090/health" 2>/dev/null || true)"
    [ -n "$ok" ] && break
    sleep 5
  done
  if [ -z "$ok" ]; then echo "Axel не ответил: docker logs axel-axel-api-1 --tail 30"; exit 1; fi
  echo "Axel-Reels: $ok"
  echo
  echo "=============================================================="
  echo "ГОТОВО (бункер). Дальше на ОКНЕ одна команда:"
  echo
  echo "curl -fsSL \"kovcheg-systems.ru/w.sh?2\" | bash -s -- site $DOMAIN"
  echo "=============================================================="
}
main "$@"
