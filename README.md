##install (mac) and start docker
* download and install virtualbox [https://www.virtualbox.org/wiki/Downloads](https://www.virtualbox.org/wiki/Downloads)
* download latest Boot2Docker: [https://github.com/boot2docker/osx-installer/releases](https://github.com/boot2docker/osx-installer/releases)
```
(init is only needed first time to create VM, or after 'boot2docker destroy')
boot2docker init
boot2docker start
$(boot2docker shellinit)
export DOCKER_HOST=tcp://$(boot2docker ip 2>/dev/null):2375
```

##start
to run a 10 node orcm cluster:
```
run-orcm.pl --nodes 10
```
500 nodes are already defined in the config (node001 - node500), so just add more to the above argument to test more endpoints

This setup includes the postgres server hosting the collect sensor data.  The image contains the postgres client, to query the data:
```
run-orcm.pl --dbcli
```
will output the command needed to run the db interface.
now run the query:
```
select node.hostname,
          data_item.name,
          data_sample.value_num,
          data_sample.units,
          data_sample.value_str
from data_sample
          inner join node on
              node.node_id = data_sample.node_id
          inner join data_item on
              data_item.data_item_id = data_sample.data_item_id;
```

##cleanup
stop and remove all containers: `run-orcm.pl --clean`

stop all containers: `docker stop $(docker ps -a -q)`

remove all conatiners: `docker rm $(docker ps -a -q)`

stop docker: `boot2docker stop`

##troubleshooting
* VPN deletes routes and makes it so that we can't connect to the VM.  Results in an error message like this:
```
2014/10/06 13:09:03 Get http://192.168.59.105:2375/v1.14/images/search?term=opensuse: dial tcp 192.168.59.105:2375: operation timed out
```
to fix:
`sudo route -n add -net 192.168.59.0/24 -interface $(VBoxManage showvminfo boot2docker-vm --machinereadable | grep hostonlyadapter | cut -d '"' -f 2)`


* TO SETUP A PROXY:

add proxy into docker VM:

ssh to docker: `boot2docker ssh`

edit profile: `sudo vi /var/lib/boot2docker/profile`

add these lines:
```
export HTTP_PROXY=<your proxy server:port>
export HTTPS_PROXY=<your proxy server:port>
```
restart docker: `sudo /etc/init.d/docker restart`

### Dockerhub:
[https://registry.hub.docker.com/repos/benmcclelland/](https://registry.hub.docker.com/repos/benmcclelland/)
