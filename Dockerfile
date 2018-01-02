FROM alpine:3.3
MAINTAINER Pål Ruud <ruudud@gmail.com>

RUN apk --no-cache add bash curl dnsmasq

RUN curl -sSL https://get.docker.com/builds/Linux/x86_64/docker-1.11.1.tgz \
        | tar zx -C /tmp &&\
    mv /tmp/docker/* /usr/local/bin/ &&\
    mkdir -p /etc/dnsmasq.d

COPY dnsmasq.conf /etc/dnsmasq.conf
COPY run.sh /run.sh

ENV DNS_DOMAIN="test"
ENV EXTRA_HOSTS=""
ENV HOSTMACHINE_IP="172.17.0.1"

EXPOSE 53/udp

ENTRYPOINT ["/run.sh"]
