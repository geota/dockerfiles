FROM fluent/fluentd:v0.12-latest
USER root
COPY entrypoint.sh /
RUN apk add --no-cache --update su-exec \
    && apk add --no-cache dumb-init --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
    && chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD fluentd -c /fluentd/etc/$FLUENTD_CONF -p /fluentd/plugins $FLUENTD_OPT
