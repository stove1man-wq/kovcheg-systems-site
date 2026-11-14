#!/usr/bin/env bash
# «Окно»: узел у другого провайдера. Принимает https от приложений и передаёт запросы
# в «бункер» (основной шлюз) по шифрованному туннелю WireGuard. Данных не хранит.
# Три шага (команды печатает сам скрипт, копируйте их из консоли):
#   1) на окне:    curl -fsSL <raw>/window-install.sh | bash -s -- prepare api.ДОМЕН IP_БУНКЕРА
#   2) на бункере: команда, которую напечатал шаг 1 (bunker-lock.sh)
#   3) на окне:    команда, которую напечатал шаг 2 (finish)
# Перед шагом 3 A-запись api.ДОМЕН должна указывать на IP окна (иначе Let's Encrypt не выдаст сертификат).
set -euo pipefail

RAW="https://kovcheg-systems.ru"
STATE=/etc/kovcheg-window.env
WG_PORT=51871
WIN_TUN=10.77.0.2
BUN_TUN=10.77.0.1
APP=/opt/kovcheg-window

own_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
}


# Ключи туннеля из общей парольной фразы: оба сервера вычисляют их сами, переносить ключи не нужно.
derive_key() {  # derive_key ИМЯ ФРАЗА -> приватный ключ (base64, 32 байта)
  python3 -c 'import hashlib,base64,sys;print(base64.b64encode(hashlib.sha256(("kovcheg-wg:"+sys.argv[1]+":"+sys.argv[2]).encode()).digest()).decode())' "$1" "$2"
}
check_code() {  # короткий контрольный код фразы: должен совпасть на обоих серверах
  python3 -c 'import hashlib,sys;print(hashlib.sha256(("code:"+sys.argv[1]).encode()).hexdigest()[:6])' "$1"
}

install_base() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq </dev/null
  apt-get install -y -qq wireguard curl ca-certificates ufw </dev/null
  if ! command -v docker >/dev/null 2>&1; then
    echo ">> Ставлю Docker (из репозитория Ubuntu)"
    apt-get install -y -qq docker.io docker-compose-v2 </dev/null
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
}

prepare() {
  local domain="${1:-}" bunker_ip="${2:-}"
  if [ -z "$domain" ] || [ -z "$bunker_ip" ]; then echo "Использование: bash -s -- prepare api.ДОМЕН IP_БУНКЕРА"; exit 1; fi
  install_base
  umask 077
  mkdir -p /etc/wireguard
  if [ ! -f /etc/wireguard/window.key ]; then
    wg genkey | tee /etc/wireguard/window.key | wg pubkey > /etc/wireguard/window.pub
  fi
  printf 'DOMAIN=%s\nBUNKER_IP=%s\n' "$domain" "$bunker_ip" > "$STATE"
  local ip pub; ip="$(own_ip)"; pub="$(cat /etc/wireguard/window.pub)"
  echo
  echo "=============================================================="
  echo "Окно подготовлено. Теперь в консоли БУНКЕРА выполните одну строку:"
  echo
  echo "curl -fsSL $RAW/b.sh | bash -s -- $ip $pub"
  echo "=============================================================="
}

# Режим «go»: одна команда на окне, ключи из парольной фразы.
go() {
  local domain="${1:-}" bunker_ip="${2:-}" pass="${3:-}"
  if [ -z "$domain" ] || [ -z "$bunker_ip" ] || [ -z "$pass" ]; then echo "Использование: bash w.sh go api.ДОМЕН IP_БУНКЕРА ФРАЗА"; exit 1; fi
  if [ "${#pass}" -lt 16 ]; then echo "Фраза слишком короткая: нужно не меньше 16 символов (латиница, цифры, дефисы)."; exit 1; fi
  install_base
  apt-get install -y -qq python3 </dev/null
  umask 077
  mkdir -p /etc/wireguard
  derive_key window "$pass" > /etc/wireguard/window.key
  wg pubkey < /etc/wireguard/window.key > /etc/wireguard/window.pub
  local bpub; bpub="$(derive_key bunker "$pass" | wg pubkey)"
  printf 'DOMAIN=%s\nBUNKER_IP=%s\n' "$domain" "$bunker_ip" > "$STATE"
  echo "Контрольный код фразы: $(check_code "$pass")  (на бункере должен быть такой же)"
  finish "$bpub"
}

finish() {
  local bpub="${1:-}"
  if [ -z "$bpub" ] || [ ! -f "$STATE" ]; then echo "Использование: bash -s -- finish КЛЮЧ_БУНКЕРА (после шага prepare)"; exit 1; fi
  # shellcheck disable=SC1090
  . "$STATE"
  umask 077
  cat > /etc/wireguard/wg0.conf <<CONF
[Interface]
PrivateKey = $(cat /etc/wireguard/window.key)
Address = $WIN_TUN/24

[Peer]
PublicKey = $bpub
Endpoint = $BUNKER_IP:$WG_PORT
AllowedIPs = $BUN_TUN/32
PersistentKeepalive = 25
CONF
  systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
  systemctl restart wg-quick@wg0

  echo ">> Жду туннель до бункера (до 40 секунд)"
  local ok=0
  for _ in $(seq 1 20); do
    local hs; hs="$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)"
    if [ -n "${hs:-}" ] && [ "$hs" != "0" ]; then ok=1; break; fi
    sleep 2
  done
  if [ "$ok" != "1" ]; then
    echo "Туннель не поднялся. Проверьте: 1) в Firewall Timeweb есть правило UDP $WG_PORT с IP этого окна; 2) бункер напечатал ГОТОВО."
    echo "Подробности: wg show"
    exit 1
  fi
  echo ">> Туннель работает. Проверяю шлюз через туннель"
  local g; g="$(curl -fsS -m 10 "http://$BUN_TUN:8080/health" || true)"
  if [ -z "$g" ]; then echo "Туннель есть, но шлюз на бункере не отвечает: docker ps и docker logs на бункере."; exit 1; fi
  echo "шлюз ответил: $g"

  local dns_ip; dns_ip="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')"
  if [ "$dns_ip" != "$(own_ip)" ]; then
    echo "ВНИМАНИЕ: $DOMAIN сейчас указывает на '${dns_ip:-ничего}', а IP окна $(own_ip). Пока запись не обновится, сертификат не выдастся."
  fi

  mkdir -p "$APP"; cd "$APP"
  cat > Caddyfile <<EOF2
$DOMAIN {
	encode gzip
	reverse_proxy http://$BUN_TUN:8080 {
		transport http {
			dial_timeout 10s
			response_header_timeout 130s
		}
	}
}
EOF2
  cat > docker-compose.yml <<'EOF2'
services:
  caddy:
    image: caddy:2
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
    restart: unless-stopped
volumes:
  caddy_data:
EOF2
  docker compose up -d </dev/null

  # Наружу только 80 и 443 (https и выдача сертификата). SSH закрыт, работа через веб-консоль.
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null

  echo ">> Жду https (сертификат выдаётся до минуты)"
  for _ in $(seq 1 24); do
    if curl -fsS -m 8 "https://$DOMAIN/health" 2>/dev/null; then
      echo; echo "ГОТОВО: https://$DOMAIN работает через туннель до бункера."
      exit 0
    fi
    sleep 5
  done
  echo "https не ответил. Проверьте A-запись $DOMAIN -> IP этого окна. Логи: docker compose -f $APP/docker-compose.yml logs --tail 30"
  exit 1
}

main() {
  if [ "$(id -u)" != "0" ]; then echo "Нужен root."; exit 1; fi
  case "${1:-}" in
    prepare) shift; prepare "$@" ;;
    finish)  shift; finish "$@" ;;
    go)      shift; go "$@" ;;
    *) echo "Режимы: go api.ДОМЕН IP_БУНКЕРА ФРАЗА | prepare ... | finish ..."; exit 1 ;;
  esac
}
main "$@"
