#!/usr/bin/env bash
# Состояние бункера: туннель, контейнеры, шлюз Барабашки, Axel-Reels (API, очередь задач, диск, копии базы).
# Запуск на бункере:  curl -fsSL "kovcheg-systems.ru/bs.sh?1" | bash
# Ничего не меняет, только читает.
main() {
  echo "== БУНКЕР: $(date '+%F %T')   аптайм: $(uptime -p)"
  echo "-- Туннель WireGuard (должен быть свежий handshake, до пары минут):"
  wg show wg0 2>&1 | grep -E 'latest handshake|transfer' | head -2
  echo "-- Контейнеры (должны быть Up):"
  docker ps --format '   {{.Names}}  {{.Status}}' 2>&1 | head -8
  echo "-- Шлюз Барабашки (10.77.0.1:8080):"
  echo "   $(curl -sS -m 8 http://10.77.0.1:8080/health 2>&1)"
  echo "-- Axel-Reels API (10.77.0.1:8090):"
  echo "   $(curl -sS -m 8 http://10.77.0.1:8090/health 2>&1)"
  echo "-- Axel: очередь задач и число пользователей:"
  docker exec axel-axel-api-1 python -c "
import sqlite3
c = sqlite3.connect('file:/data/axel.db?mode=ro', uri=True)
rows = c.execute('SELECT status, COUNT(*) FROM jobs GROUP BY status').fetchall()
print('   задачи:', dict(rows) if rows else 'нет')
print('   пользователей:', c.execute('SELECT COUNT(*) FROM users').fetchone()[0])
" 2>&1 | head -4
  echo "-- Диск (Use% до 80 нормально):"
  df -h / /var/lib/kovcheg-axel 2>/dev/null | awk 'NR==1||!seen[$1]++' | sed 's/^/   /'
  echo "-- Копии базы Axel (последние 3):"
  ls -1t /var/lib/kovcheg-axel/backups 2>/dev/null | head -3 | sed 's/^/   /'
  echo "-- Последние ошибки Axel (если пусто, ошибок нет):"
  docker logs --tail 300 axel-axel-api-1 2>&1 | grep -iE 'error|traceback|exception' | tail -5 | cut -c1-160 | sed 's/^/   /'
  echo "== Конец. Если что-то не так, пришлите этот вывод целиком."
}
main
