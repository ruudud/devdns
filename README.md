# devdns
Make docker containers discoverable via DNS for development environments, like
when running a bunch of containers on your laptop. Useful for
**container to container communication**, or just an easy way of **reaching
containers from the host machine**.

[![](https://images.microbadger.com/badges/image/ruudud/devdns.svg)](https://microbadger.com/images/ruudud/devdns "Get your own image badge on microbadger.com")


## Running

```sh
docker run -d --name devdns -p 53:53/udp \
      -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns
```

devdns requires access to the Docker socket to be able to query for container
names and IP addresses, in addition to listen to start/stop events.

Binding port 53 on the host machine is optional, but will make it easier when
configuring local resolving.

The DNS server running in devdns is set to proxy requests for unknown hosts to
Google's DNS server 8.8.8.8.
It also adds a wildcard record (normally `*.test`, see `DNS_DOMAIN` below)
pointing back at the host machine (bridge IP in Linux), to facilitate
communication when running a combination of services "inside" and "outside" of
Docker.


## Using

### Container ↔ Container
When running other containers, specify the devdns container IP as the DNS to
use:

```sh
$ docker run -d --name devdns -p 53:53/udp \
  -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns
$ docker run -d --name redis redis
$ docker run -it --rm \
  --dns=`docker inspect -f "{{ .NetworkSettings.IPAddress }}" devdns` debian \
  ping redis.test
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

    --dns 172.17.0.1 --dns-search test

Replace `test` with whatever you set as config for `DNS_DOMAIN`.

`172.17.0.1` is the default IP of the Docker bridge, and port 53 on this host
should be reachable from within all started containers given that you've
included `-p 53:53/udp` when starting the devdns container.

[Docker configuring docs]: https://docs.docker.com/articles/configuring/#configuring-docker
[Docker systemd docs]: https://docs.docker.com/articles/systemd/#custom-docker-daemon-options
[boot2docker faq]: https://github.com/boot2docker/boot2docker/blob/master/doc/FAQ.md#local-customisation-with-persistent-partition


### Host Machine → Containers
You will need to add some configuration to your OS resolving mechanism.  
**NOTE**: This is only practical if you added `-p 53:53/udp` when starting
devdns.

#### OSX
Create a file `/etc/resolver/test` containing

    nameserver <listen address of devdns>

In OSX, there's a good chance you're using boot2docker, so the listen address
will probably be the output of `boot2docker ip`.
Please note that the name of the file created in `/etc/resolver` has to match
the value of the `DNS_DOMAIN` setting (default "test").


#### Linux / Ubuntu
Nowadays, direct edits of `/etc/resolv.conf` will be removed at reboot.
Thus, the best place to add extra resolvers in Linux, is to use your network
configurator. YMMV. This means NetworkManager (see section below), WICD, or
manually using `/etc/network/interfaces`:

```
auto p3p1
iface p3p1 inet dhcp
dns-search test
dns-nameservers 127.0.0.1
```

Alternatively, edit `/etc/dhcp/dhclient.conf` instead. Uncomment or add the
following line:

```
supersede domain-name "test";
prepend domain-name-servers 127.0.0.1;
```


## Configuration

 * `DNS_DOMAIN`: set the local domain used. (default: **test**)
 * `HOSTMACHINE_IP`: IP address of non-matching queries (default:
   **172.17.0.1**)
 * `EXTRA_HOSTS`: list of extra records to create, space-separated string of
   host=ip pairs. (default: **''**)
 * `NAMING`: set to "full" to convert `_` to `-` (default: up to first `_` of
   container name)
 * `NETWORK`: set the network to use. (default: **bridge**)

Example:

```sh
docker run -d -v /var/run/docker.sock:/var/run/docker.sock \
  -e DNS_DOMAIN=docker \
  -e HOSTMACHINE_IP=192.168.1.1 \
  -e NAMING=full \
  -e NETWORK=mynetwork \
  -e EXTRA_HOSTS="dockerhost=172.17.0.1 doubleclick.net=127.0.0.1" \
  ruudud/devdns
```


## Caveats

### Container name to DNS record conversion
RFC 1123 states that `_` are not allowed in DNS records, but Docker allows it
in container names. devdns ignores `_` and whatever follows, allowing multiple
simultaneous containers with matching names to run at the same time.

The DNS will resolve to the lastly added container, and try to re-toggle the
previous matching container when stopping the currently active one.

Example:
```sh
# (devdns already running)
$ docker run -d --name redis_local-V1 redis
$ dig redis.test     # resolves to the IP of redis_local-V1

$ docker run -d --name redis_test redis
$ dig redis.test     # resolves to the IP of redis_test

$ docker stop redis_test
$ dig redis.test     # resolves to the IP of redis_local-V1

$ docker stop redis_local-V1
$ dig redis.test     # resolves to the IP of the host machine (default)
```

### NetworkManager on Ubuntu
If you're using **NetworkManager**, you should disable the built-in DNSMasq to
get the port binding of port 53 to work.

Edit `/etc/NetworkManager/NetworkManager.conf` and comment out the line
`dns=dnsmasq` so it looks like this:

    # dns=dnsmasq

Restart using `sudo service network-manager restart`.

Now you should be able to do
```sh
docker run -d -v /var/run/docker.sock:/var/run/docker.sock \
    -p 53:53/udp ruudud/devdns
```

