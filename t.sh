#!/usr/bin/env bash
# Проверка шлюза на бункере изнутри: регистрация тестового устройства, вопрос модели, последние записи журнала.
# Запуск на бункере:  curl -fsSL "kovcheg-systems.ru/t.sh?1" | bash
main() {
  local base="http://10.77.0.1:8080" id key reply
  id="bunker-test-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo ">> Здоровье:"; curl -sS -m 8 "$base/health"; echo
  echo ">> Регистрация тестового устройства:"
  reply="$(curl -sS -m 15 -X POST "$base/v1/register" -H 'content-type: application/json' -d "{\"device_id\":\"$id\"}")"; echo "$reply"
  key="$(echo "$reply" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')"
  if [ -z "$key" ]; then echo "Ключ не получен."; else
    echo ">> Вопрос модели (до 60 секунд):"
    curl -sS -m 60 -X POST "$base/v1/chat" -H "Authorization: Bearer $key" -H 'content-type: application/json' \
      -d '{"messages":[{"role":"user","content":"Скажи привет одним словом"}]}'; echo
  fi
  echo ">> Запросы к шлюзу (без мусора от сканеров), последние 20:"
  docker logs --tail 1500 deploy-gateway-1 2>&1 | grep -E '/v1/|/health' | tail -20 | cut -c1-200
}
main
