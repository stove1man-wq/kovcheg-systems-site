#!/usr/bin/env bash
# Инвентаризация сервера (только чтение). Ничего не меняет, секреты не выводит и не читает.
# Запуск на сервере:  curl -fsSL "kovcheg-systems.ru/inv.sh?1" | bash
main() {
  mask() { sed -E 's/((key|token|secret|pass(word)?|auth)[a-z_]*)=[^ ]+/\1=***/Ig'; }
  echo "== ИНВЕНТАРИЗАЦИЯ $(date -Is) =="
  echo "-- Хост: $(hostname)   ОС: $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")   Виртуализация: $(systemd-detect-virt 2>/dev/null)"
  echo "-- Аптайм: $(uptime -p)"
  echo "-- Провайдер сети (по внешнему адресу, адрес не выводится): $(curl -s -m 6 https://ipinfo.io/org 2>/dev/null || echo 'не определён')"
  echo "-- CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)   ядер: $(nproc)"
  echo "-- RAM: $(free -m | awk '/Mem:/ {print $2" МБ, занято "$3" МБ"}')   swap: $(free -m | awk '/Swap:/ {print $2" МБ"}')"
  echo "-- GPU: $(command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || echo 'нет')"
  echo "-- Диски:"; df -hT -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR==1 || $NF ~ /^\//'
  echo "-- Docker:"; if command -v docker >/dev/null; then docker ps --format '   {{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | head -30; docker system df 2>&1 | head -6; else echo '   нет'; fi
  echo "-- Открытые порты (только адрес и порт):"; ss -tlnH 2>/dev/null | awk '{print "   "$4}' | sort -u | head -30
  echo "-- Файрвол:"; ufw status 2>&1 | head -10
  echo "-- WireGuard:"; if command -v wg >/dev/null; then wg show interfaces 2>&1; for i in $(wg show interfaces 2>/dev/null); do echo "   $i: пиров $(wg show $i peers | wc -l)"; wg show $i latest-handshakes | awk '{print "   последнее рукопожатие (unix): "$2}'; done; else echo '   нет'; fi
  echo "-- Домены в Caddy:"; for f in /opt/kovcheg-window/Caddyfile /etc/caddy/Caddyfile /root/Barabashka/server/deploy/Caddyfile; do [ -f "$f" ] && { echo "   $f"; grep -E '^[a-zA-Z0-9.-]+[ ]*\{' "$f" | sed 's/^/     /'; }; done
  echo "-- Базы и копии (имена и размеры):"; find /root /opt /var/lib -maxdepth 5 \( -name '*.db' -o -name '*.sqlite*' -o -name 'backups' \) -not -path '*/proc/*' 2>/dev/null | head -20 | while read p; do echo "   $(du -sh "$p" 2>/dev/null | cut -f1)  $p"; done
  echo "-- Крупные каталоги:"; du -xsh /root/* /opt/* /srv/* /var/lib/docker 2>/dev/null | sort -h | tail -8 | sed 's/^/   /'
  echo "-- Задания cron (значения секретов скрыты):"; (crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null) | grep -v '^#' | grep -v '^$' | mask | head -15 | sed 's/^/   /'
  echo "-- Упавшие службы:"; systemctl --failed --no-legend 2>/dev/null | head -5 | sed 's/^/   /'
  echo "-- Последние входы:"; last -n 5 -a 2>/dev/null | head -6 | sed 's/^/   /'
  echo "== КОНЕЦ. Скопируйте вывод целиком и пришлите в чат. =="
}
main
