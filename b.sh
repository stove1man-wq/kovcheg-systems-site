#!/usr/bin/env bash
# «Бункер»: основной шлюз. Закрывается от всего мира: наружу открыт только UDP-порт WireGuard
# и только для адреса окна. Шлюз слушает ТОЛЬКО внутри туннеля (10.77.0.1:8080), сертификаты и домен бункеру не нужны.
# Запуск (строку печатает window-install.sh prepare):
#   curl -fsSL <raw>/bunker-lock.sh | bash -s -- IP_ОКНА КЛЮЧ_ОКНА
# Откат доступа при ошибке: ufw disable
set -euo pipefail

RAW="https://kovcheg-systems.ru"
WG_PORT=51871
WIN_TUN=10.77.0.2
BUN_TUN=10.77.0.1

find_deploy_dir() {
  local d
  d="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' deploy-gateway-1 2>/dev/null || true)"
  if [ -z "$d" ] || [ ! -f "$d/docker-compose.prod.yml" ]; then
    d="$(dirname "$(find / -maxdepth 5 -name docker-compose.prod.yml -path '*server/deploy*' 2>/dev/null | head -1)")"
  fi
  echo "$d"
}

main() {
  local win_ip="${1:-}" win_pub="${2:-}"
  if [ "$(id -u)" != "0" ]; then echo "Нужен root."; exit 1; fi
  if [ -z "$win_ip" ] || [ -z "$win_pub" ]; then echo "Использование: bash -s -- IP_ОКНА КЛЮЧ_ОКНА"; exit 1; fi

  export DEBIAN_FRONTEND=noninteractive
  echo ">> Ставлю WireGuard и файрвол"
  apt-get update -qq </dev/null
  apt-get install -y -qq wireguard ufw python3 </dev/null

  echo ">> Туннель"
  umask 077
  mkdir -p /etc/wireguard
  if [ ! -f /etc/wireguard/bunker.key ]; then
    wg genkey | tee /etc/wireguard/bunker.key | wg pubkey > /etc/wireguard/bunker.pub
  fi
  cat > /etc/wireguard/wg0.conf <<CONF
[Interface]
PrivateKey = $(cat /etc/wireguard/bunker.key)
Address = $BUN_TUN/24
ListenPort = $WG_PORT

[Peer]
PublicKey = $win_pub
AllowedIPs = $WIN_TUN/32
CONF
  systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
  systemctl restart wg-quick@wg0

  echo ">> Docker: явные DNS и запуск после туннеля"
  local before after
  before="$(cat /etc/docker/daemon.json 2>/dev/null || true)"
  python3 - <<'PY'
import json, os
p = '/etc/docker/daemon.json'
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d['dns'] = ['77.88.8.8', '1.1.1.1', '8.8.8.8']
json.dump(d, open(p, 'w'), indent=2)
PY
  after="$(cat /etc/docker/daemon.json)"
  mkdir -p /etc/systemd/system/docker.service.d
  printf '[Unit]\nAfter=wg-quick@wg0.service\nWants=wg-quick@wg0.service\n' > /etc/systemd/system/docker.service.d/wg.conf
  systemctl daemon-reload
  if [ "$before" != "$after" ]; then systemctl restart docker; sleep 3; fi

  echo ">> Шлюз только внутри туннеля"
  local dir; dir="$(find_deploy_dir)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "Не нашёл папку server/deploy со шлюзом."; exit 1; fi
  cd "$dir"
  cat > docker-compose.bunker.yml <<EOF2
# Шлюз в режиме «бункер»: порт только на адресе туннеля, Caddy не нужен.
services:
  gateway:
    build: ..
    env_file: ../.env
    environment:
      BARABASHKA_DATA: /data
    volumes:
      - ../data:/data
    ports:
      - "$BUN_TUN:8080:8080"
    restart: unless-stopped
EOF2
  touch .bunker
  rm -f .env   # в нём был старый домен (DOMAIN=...): бункеру домен не нужен
  docker compose -f docker-compose.bunker.yml up -d --build --remove-orphans </dev/null
  docker volume rm deploy_caddy_data >/dev/null 2>&1 || true   # сертификаты и учётка Let's Encrypt старого домена

  # Автообновление со старыми скриптами подняло бы Caddy на 80/443: выключаем до переноса новых скриптов.
  if [ -f /etc/cron.d/barabashka-update ]; then
    rm -f /etc/cron.d/barabashka-update
    echo "Ночное автообновление выключено (включу после переноса поддержки бункера в server-stable)."
  fi

  echo ">> Файрвол: только UDP $WG_PORT с $win_ip; SSH только из туннеля"
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow from "$win_ip" to any port "$WG_PORT" proto udp >/dev/null
  ufw allow in on wg0 to any port 22 proto tcp >/dev/null
  ufw --force enable >/dev/null

  echo ">> Проверка шлюза внутри бункера"
  local ok=""
  for _ in $(seq 1 12); do
    ok="$(curl -fsS -m 4 "http://$BUN_TUN:8080/health" 2>/dev/null || true)"
    [ -n "$ok" ] && break
    sleep 5
  done
  if [ -z "$ok" ]; then echo "Шлюз не ответил: docker compose -f $dir/docker-compose.bunker.yml logs --tail 30"; exit 1; fi
  echo "шлюз: $ok"

  echo
  echo "=============================================================="
  echo "ГОТОВО. Если ещё не сделали: в панели Timeweb, Firewall-группа сервера, добавьте"
  echo "входящее правило: протокол UDP, порт $WG_PORT, источник $win_ip (больше ничего не открывать)."
  echo "Затем в консоли ОКНА выполните одну строку:"
  echo
  echo "curl -fsSL $RAW/w.sh | bash -s -- finish $(cat /etc/wireguard/bunker.pub)"
  echo "=============================================================="
}
main "$@"
