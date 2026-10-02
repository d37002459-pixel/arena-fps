#!/bin/sh
# Запуск на Render: Godot-сервер в фоне, nginx отдаёт сайт и проксирует /ws.
PORT="${PORT:-10000}"
export PORT
envsubst '${PORT}' < /app/server/nginx.conf > /etc/nginx/nginx.conf

(
  while true; do
    godot --headless --path /app -- --server
    echo "game server exited, restarting in 2s"
    sleep 2
  done
) &

exec nginx -g 'daemon off;'
