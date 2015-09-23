# devdns
Make docker containers discoverable via DNS for development environments, like
when running a bunch of containers on your laptop. Useful for
**container to container communication**, or just an easy way of **reaching
containers from the host machine**.

This image will *not* forward DNS requests.


## Running

    docker run -d --name devdns -p 53:53/udp \
      -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns

devdns requires access to the Docker socket to be able to query for container
names and IP addresses, in addition to listen to new events. 

Binding port 53 on the host machine is optional, but will make it easier when
configuring local resolving.


## Using

### Container ↔ Container
When running other containers, specify the devdns container IP as the DNS to
use:

```
$ docker run -d --name devdns -p 53:53/udp \
  -v /var/run/docker.sock:/var/run/docker.sock ruudud/devdns
$ docker run --d --name redis redis
$ docker run -it --rm \
  --dns=`docker inspect -f "{{ .NetworkSettings.IPAddress }}" devdns` debian \
  ping redis.dev
```

Please note that the `--dns` flag will prepend the given DNS server to the
Docker default (normally `8.8.8.8`), so lookups for external addresses will
still work.


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


