# devdns
Make docker containers discoverable via DNS for development environments, like
when running a bunch of containers on your laptop. Useful for
**container to container communication**, or just an easy way of **reaching
containers from the host machine**.

![Image Size](https://img.shields.io/microbadger/image-size/ruudud/devdns)
![Docker Pulls](https://img.shields.io/docker/pulls/ruudud/devdns)

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
$ docker run -d --name redis redis:alpine
$ docker run -it --rm \
  --dns=`docker inspect -f "{{ range.NetworkSettings.Networks }}{{ .IPAddress }}{{ end }}" devdns | head -n1` alpine \
  ping redis.test
```

Please note that the `--dns` flag will prepend the given DNS server to the
Docker default, so lookups for external addresses will still work.

#### Docker Daemon Configuration
If you want devdns to be added by default to all new containers, you need to
add some custom Docker daemon options as per the [dockerd reference][].

The exact process to set these options varies by the way you launch the Docker
daemon and/or the underlying OS:

 * systemd (Ubuntu, Debian, RHEL 7, CentOS 7, Fedora, Archlinux) —
   `sudo systemctl edit docker.service`, change the `ExecStart` line
 * Ubuntu 12.04 — set `DOCKER_OPTS` in `/etc/default/docker`
 * OS/X — select *Preferences* -> *Daemon* -> *Advanced*

The extra options you'll have to add is

    --dns 172.17.0.1 --dns-search test

Replace `test` with whatever you set as config for `DNS_DOMAIN`.

`172.17.0.1` is the default IP of the Docker bridge, and port 53 on this host
should be reachable from within all started containers given that you've
included `-p 53:53/udp` when starting the devdns container.

> Note: There are some caveats with Docker and how it manages a container's
> `/etc/resolv.conf` file. Unless you do something exotic, like parsing this
> file, you should be fine. See [Docker DNS docs][] for more information.

[dockerd reference]: https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-dns-options
[Docker DNS docs]: https://docs.docker.com/v17.09/engine/userguide/networking/configure-dns/


### Host Machine → Containers
You will need to add some configuration to your OS DNS resolving mechanism to
make it query devdns.  
**NOTE**: This is only practical if you added `-p 53:53/udp` when starting
devdns.

#### Linux
Nowadays, direct edits of `/etc/resolv.conf` will often be removed at reboot.
Thus, the best place to add extra resolvers in Linux, is to use your network
configurator. YMMV. This means NetworkManager (see [section
below](#networkmanager-on-ubuntu)), WICD, or manually using
`/etc/network/interfaces`:

```
auto p3p1
iface p3p1 inet dhcp
dns-search test
dns-nameservers 127.0.0.1
```

#### OSX
Create a file `/etc/resolver/test` containing

    nameserver 127.0.0.1

In OSX and Docker for Mac, port binding should work directly on the host
machine. Please note that the name of the file created in `/etc/resolver` has
to match the value of the `DNS_DOMAIN` setting (default "test").



## Configuration

 * `DNS_DOMAIN`: set the local domain used. (default: **test**)
 * `HOSTMACHINE_IP`: IP address of non-matching queries (default:
   **172.17.0.1**)
 * `EXTRA_HOSTS`: list of extra records to create, space-separated string of
   host=ip pairs. (default: **''**)
 * `NAMING`: set to "full" to convert `_` to `-` (default: up to first `_` of
   container name)
 * `NETWORK`: set the network to use. Set to "auto" to automatically use the
   first network interface (e.g. when using docker-compose) (default:
   **bridge**)

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
