FROM alpine:3.2

RUN apk --update add \
    bash \
    curl \
    dnsmasq && \
    rm -rf /var/cache/apk/*

RUN curl -L https://get.docker.com/builds/Linux/x86_64/docker-1.8.0 > /usr/local/bin/docker && \
  chmod +x /usr/local/bin/docker

RUN mkdir -p /etc/dnsmasq.d

ADD dnsmasq.conf /etc/dnsmasq.conf
ADD run.sh /run.sh

ENV DNS_DOMAIN="dev"
ENV EXTRA_HOSTS=""

EXPOSE 53 53/udp

CMD ["/run.sh"]

