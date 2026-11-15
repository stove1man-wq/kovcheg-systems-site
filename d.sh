#!/usr/bin/env bash
# Бункер получает доступ к приватному репозиторию (ключ только для чтения) и включает ночное автообновление.
# Запуск на бункере:  curl -fsSL "kovcheg-systems.ru/d.sh?1" | bash
# Скрипт печатает открытый ключ: его нужно один раз добавить на GitHub (Settings -> Deploy keys, без права записи).
# Дальше скрипт ждёт доступа сам и доделывает всё без ваших действий.
set -euo pipefail

KEY=/root/.ssh/barabashka_deploy
REPO_URL="git@github-barabashka:stove1man-wq/Barabashka.git"

find_deploy_dir() {
  local d
  d="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' deploy-gateway-1 2>/dev/null || true)"
  if [ -z "$d" ] || [ ! -f "$d/update.sh" ]; then
    d="$(dirname "$(find / -maxdepth 5 -name update.sh -path '*server/deploy*' 2>/dev/null | head -1)")"
  fi
  echo "$d"
}

main() {
  if [ "$(id -u)" != "0" ]; then echo "Нужен root."; exit 1; fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq git openssh-client </dev/null
  mkdir -p /root/.ssh; chmod 700 /root/.ssh
  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "bunker-deploy" -f "$KEY"
  if ! grep -q "github-barabashka" /root/.ssh/config 2>/dev/null; then
    cat >> /root/.ssh/config <<CONF
Host github-barabashka
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CONF
  fi
  chmod 600 /root/.ssh/config

  local dir; dir="$(find_deploy_dir)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "Не нашёл папку server/deploy со шлюзом."; exit 1; fi
  local repo; repo="$(git -C "$dir" rev-parse --show-toplevel)"

  echo
  echo "=============================================================="
  echo "Откройте https://github.com/stove1man-wq/Barabashka/settings/keys/new"
  echo "Title: bunker. Key: вставьте строку ниже целиком. Галочку «Allow write access» НЕ ставьте."
  echo
  cat "$KEY.pub"
  echo "=============================================================="
  echo "Жду, пока ключ появится на GitHub (до 15 минут)..."
  local ok=0
  for _ in $(seq 1 90); do
    if git ls-remote "$REPO_URL" server-stable >/dev/null 2>&1; then ok=1; break; fi
    sleep 10
  done
  if [ "$ok" != "1" ]; then echo "Доступ не появился. Добавьте ключ и запустите команду ещё раз."; exit 1; fi

  echo ">> Доступ есть. Переключаю репозиторий и включаю автообновление"
  git -C "$repo" remote set-url origin "$REPO_URL"
  cd "$dir"
  bash enable-auto-update.sh
  echo
  echo "ГОТОВО: автообновление включено (ежедневно в 05:00), шлюз обновлён."
}
main
