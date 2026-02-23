Deploy ubuntu 22.04
assign 3 ENIs, two with public IPs, and one private
Create SG accordingly
Login to instance and start running commands
```
sudo -s
```
```
apt update -y 
```
```
apt install python3-pip -y
```
```
apt install net-tools -y
```
```
snap refresh --hold=forever
```
```
snap install lxd
```
```
apt install tmux -y
```
```
snap install aws-cli --classic
```

Ensure the YAML file below is created in the directory /tmp/lxd.yaml
LXD Default Configuration file
```
config:
  images.auto_update_cached: false
storage_pools:
- name: default
  driver: dir
profiles:
- devices:
    root:
      path: /
      pool: default
      type: disk
  name: default
```

Initiate lxd
```
cat /tmp/lxd.yaml | lxd init --preseed
```

```
aws --region us-east-1 s3 cp s3://janhaus-fra-vyos-bucket/vyos_dxgl-1.3.3-bc64a3a-5_lxd_amd64.tar.gz /tmp/vyos.tar.gz
```

```
lxc image import /tmp/vyos.tar.gz --alias vyos
```

Create the config file for the router instance and put it in /tmp/router.yaml
```
architecture: x86_64
config:
  limits.cpu: '1'
  limits.memory: 2048MiB
devices:
  eth0:
    nictype: physical
    parent: ens6
    type: nic
  eth1:
    nictype: physical
    parent: ens7
    type: nic
```

Deploy the router instance
```
cat /tmp/router.yaml | lxc init vyos router
```
Update the base configuration file of the router
```
interfaces {
	ethernet eth0 {
		address dhcp
		description OUTSIDE
	}
	ethernet eth1 {
		address dhcp
		description INSIDE
	}

	loopback lo {
	}
```

```
lxc start router
```



#### Script Test
```
bash
# Copy script to VyOS container
lxc file push vyos-script.sh router/tmp/vyos-script.sh

# Make executable and run
lxc exec router -- chmod +x /tmp/vyos-script.sh
lxc exec router -- /tmp/vyos-script.sh
```

vyos-script.sh
```
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth0 description 'OUTSIDE'
set interfaces ethernet eth0 address dhcp
set interfaces ethernet eth0 dhcp-options default-route-distance 10
set interfaces ethernet eth1 description 'INSIDE'
set interfaces ethernet eth1 address dhcp
set interfaces ethernet eth1 dhcp-options default-route-distance 210
commit
exit
```




Separate config.boot.default file
```
interfaces {
     ethernet eth0 {
         address dhcp
         description OUTSIDE
     }
     ethernet eth1 {
         address dhcp
         description INSIDE
     }
     loopback lo {
     }
 }
 system {
     config-management {
         commit-revisions 100
     }
     console {
         device ttyS0 {
             speed 115200
         }
     }
     host-name vyos
     login {
         user vyos {
             authentication {
                 encrypted-password $6$QxPS.uk6mfo$9QBSo8u1FkH16gMyAVhus6fU3LOzvLR9Z9.82m3tiHFAxTtIkhaZSWssSgzt4v4dGAL8rhVQxTg0oAG9/q11h/
                 plaintext-password ""
             }
         }
     }
     ntp {
         server time1.vyos.net {
         }
         server time2.vyos.net {
         }
         server time3.vyos.net {
         }
     }
     syslog {
         global {
             facility all {
                 level info
             }
             facility protocols {
                 level debug
             }
         }
     }
 }
```


### Bash Prompt for Instance Configuration

Raw data for Amazon Q

Installation commands
sudo -s
apt update -y 
apt install python3-pip -y
apt install awscli -y
apt install net-tools -y
snap refresh --hold=forever
snap install lxd
apt install tmux -y

Ensure the YAML file below is created in the directory /tmp/lxd.yaml
LXD Default Configuration file
config:
  images.auto_update_cached: false
storage_pools:
- name: default
  driver: dir
profiles:
- devices:
    root:
      path: /
      pool: default
      type: disk
  name: default

Initiate lxd
cat /tmp/lxd.yaml | lxd init --preseed

Download and import image from S3
aws --region eu-central-1 s3 cp s3://janhaus-fra-vyos-bucket/vyos_dxgl-1.3.3-bc64a3a-5_lxd_amd64.tar.gz /tmp/vyos.tar.gz

Set Alias to that of vyos for the container image
lxc image import /tmp/vyos.tar.gz --alias vyos

Create the config file for the router instance and put it in /tmp/router.yaml
architecture: x86_64
config:
  limits.cpu: '1'
  limits.memory: 2048MiB
devices:
  eth0:
    nictype: physical
    parent: ens6
    type: nic
  eth1:
    nictype: physical
    parent: ens7
    type: nic

Deploy the router instance
cat /tmp/router.yaml | lxc init vyos router

Update the base configuration file of the router

interfaces {
	ethernet eth0 {
		address dhcp
		description OUTSIDE
	}
	ethernet eth1 {
		address dhcp
		description INSIDE
	}
	loopback lo {
	}

Start the container
lxc start router

# to test: sudo lxc exec router -- su - vyos
