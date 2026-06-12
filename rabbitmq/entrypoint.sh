#!/bin/sh
set -eu

docker-entrypoint.sh rabbitmq-server &
rabbitmq_pid=$!

shutdown() {
  kill -TERM "$rabbitmq_pid" 2>/dev/null || true
  wait "$rabbitmq_pid" || true
}

trap shutdown TERM INT

until rabbitmq-diagnostics -q ping; do
  if ! kill -0 "$rabbitmq_pid" 2>/dev/null; then
    wait "$rabbitmq_pid"
    exit $?
  fi
  sleep 1
done

rabbitmqctl await_startup

if rabbitmqctl list_users --silent | cut -f1 | grep -Fxq "$RABBITMQ_DEFAULT_USER"; then
  rabbitmqctl change_password "$RABBITMQ_DEFAULT_USER" "$RABBITMQ_DEFAULT_PASS"
else
  rabbitmqctl add_user "$RABBITMQ_DEFAULT_USER" "$RABBITMQ_DEFAULT_PASS"
fi

if ! rabbitmqctl list_vhosts --silent | grep -Fxq "$RABBITMQ_DEFAULT_VHOST"; then
  rabbitmqctl add_vhost "$RABBITMQ_DEFAULT_VHOST"
fi

rabbitmqctl set_user_tags "$RABBITMQ_DEFAULT_USER" administrator
rabbitmqctl set_permissions -p "$RABBITMQ_DEFAULT_VHOST" "$RABBITMQ_DEFAULT_USER" '.*' '.*' '.*'

wait "$rabbitmq_pid"
