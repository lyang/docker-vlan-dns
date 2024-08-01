FROM docker.io/library/docker:cli

RUN apk upgrade --no-cache && \
    apk add --no-cache bash dnsmasq jq && \
    rm -rf /tmp/* /var/cache/apk/* /var/tmp/*

ENV HOSTSDIR='/opt/dnsmasq'

RUN mkdir $HOSTSDIR

COPY dnsmasq.conf /etc/dnsmasq.conf
COPY entrypoint.sh /usr/local/bin

ENV CONF_DIR='/etc/dnsmasq.d'
ENV DNS_SERVERS='1.1.1.1;1.0.0.1;8.8.8.8;8.8.4.4'

EXPOSE 53/udp

ENTRYPOINT ["entrypoint.sh"]
