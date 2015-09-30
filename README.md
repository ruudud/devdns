# devdns
Make docker containers discoverable via DNS for development environments, like
when running a bunch of containers on your laptop. Useful for
**container to container communication**, or just an easy way of **reaching
containers from the host machine**.


## Running

    docker run -d --name devdns -p 53:53/udp \
      -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns

devdns requires access to the Docker socket to be able to query for container
names and IP addresses, in addition to listen to start/stop events.

Binding port 53 on the host machine is optional, but will make it easier when
configuring local resolving.

The DNS server running in devdns is set to proxy requests for unknown hosts to
Google's DNS server 8.8.8.8.
It also adds a wildcard record (normally `*.dev`, see `DNS_DOMAIN` below)
pointing back at the host machine (bridge IP in Linux), to facilitate
communication when running a combination of services "inside" and "outside" of
Docker.


## Using

### Container ↔ Container
When running other containers, specify the devdns container IP as the DNS to
use:

```
$ docker run -d --name devdns -p 53:53/udp \
  -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns
$ docker run -d --name redis redis
$ docker run -it --rm \
  --dns=`docker inspect -f "{{ .NetworkSettings.IPAddress }}" devdns` debian \
  ping redis.dev
```

Please note that the `--dns` flag will prepend the given DNS server to the
Docker default (normally `8.8.8.8`), so lookups for external addresses will
still work.

#### Docker Daemon Configuration
If you want devdns to be added by default to all new containers, you need to
add some custom Docker daemon options. The place to put this config varies:

 * Ubuntu <= 14.10: `/etc/default/docker`, see the
   [Docker configuring docs][]
 * Ubuntu >= 15.04: `/etc/systemd/system/docker.service`, see the
   [Docker systemd docs][]
 * OSX boot2docker: `/var/lib/boot2docker/profile`, see the
   [boot2docker faq][]

The extra options you'll have to add is

    --dns 172.17.42.1 --dns-search dev

Replace `dev` with whatever you set as config for `DNS_DOMAIN`.

`172.17.42.1` is the default IP of the Docker bridge, and port 53 on this host
should be reachable from within all started containers given that you've
included `-p53:53/upd` when starting the devdns container.

[Docker configuring docs]: https://docs.docker.com/articles/configuring/#configuring-docker
[Docker systemd docs]: https://docs.docker.com/articles/systemd/#custom-docker-daemon-options
[boot2docker faq]: https://github.com/boot2docker/boot2docker/blob/master/doc/FAQ.md#local-customisation-with-persistent-partition


### Host Machine → Containers
You will need to add some configuration to your OS resolving mechanism.

#### OSX
Create a file `/etc/resolver/dev` containing

    nameserver <listen address of devdns>

In OSX, there's a good chance you're using boot2docker, so the listen address
will probably be the output of `boot2docker ip`.
Please note that the name of the file created in `/etc/resolver` has to match
the value of the `DNS_DOMAIN` setting (default "dev").


#### Linux / Ubuntu
Edit `/etc/resolv.conf`, at the top of the file, add:

    nameserver 127.0.0.1

Or, if you didn't specify `-p 53:53/udp` when starting devdns, use:

    nameserver <listen address of devdns>

Please note that this change will be removed up on reboot. To make the change
permanent, you have to use your network configurator.


## Configuration

 * `DNS_DOMAIN`: set the local domain used. (default: dev)
 * `EXTRA_HOSTS`: list of extra records to create, space-separated string of
   host=ip pairs. (default: '')

Example:

```
docker run -d -v /var/run/docker.sock:/var/run/docker.sock \
  -e DNS_DOMAIN=docker \
  -e EXTRA_HOSTS="dockerhost=172.17.42.1 doubleclick.net=127.0.0.1" \
  ruudud/devdns
```


## Caveats
RFC 1123 states that `_` are not allowed in DNS records, but Docker allows it
in container names. These are replaced with `-` before adding the record.
