#!/usr/bin/dumb-init /bin/sh

if [ "$(id -u)" = '0' ]; then
  uid=${FLUENTD_UID:-1000}

  cat /etc/passwd | grep fluent >/dev/null
  if [[ "${?}" == "0" ]]; then
      deluser fluent
  fi

  adduser -D -g '' -u ${uid} -h /home/fluent fluent
  chown -R fluent /home/fluent
  chown -R fluent /fluentd

  exec su-exec fluent "$0" "$@"
fi

exec $@
