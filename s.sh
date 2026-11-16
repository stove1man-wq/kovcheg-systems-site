#!/usr/bin/env bash
# Состояние окна: туннель, Docker, Caddy, шлюз через туннель, https с самого окна.
# Запуск на окне:  curl -fsSL "kovcheg-systems.ru/s.sh?1" | bash
main() {
  . /etc/kovcheg-window.env 2>/dev/null || true
  echo ">> Время: $(date -Is)   Аптайм: $(uptime -p)"
  echo ">> wg-quick@wg0: $(systemctl is-active wg-quick@wg0)   docker: $(systemctl is-active docker)"
  echo ">> Туннель:"; wg show wg0 2>&1 | grep -E 'peer|endpoint|latest handshake|transfer' | head
  echo ">> Контейнеры:"; docker ps --format '{{.Names}}  {{.Status}}' 2>&1 | head
  echo ">> Шлюз через туннель:"; curl -sS -m 8 http://10.77.0.1:8080/health 2>&1; echo
  echo ">> Axel-Reels через туннель (10.77.0.1:8090):"; curl -sS -m 8 http://10.77.0.1:8090/health 2>&1; echo
  echo ">> Домены в Caddy (должны быть api и axel):"; grep -E '^[a-z0-9.-]+ \{' /opt/kovcheg-window/Caddyfile 2>&1
  echo ">> https axel с самого окна:"; curl -sS -m 12 https://axel.doroga-bunker.ru/health 2>&1; echo
  echo ">> https с самого окна (${DOMAIN:-?}):"; curl -sS -m 12 "https://${DOMAIN:-api.doroga-bunker.ru}/health" 2>&1; echo
  echo ">> Файрвол:"; ufw status 2>&1 | head -8
  echo ">> Журнал Caddy (последние 8):"; docker logs --tail 8 kovcheg-window-caddy-1 2>&1 | cut -c1-180
}
main
