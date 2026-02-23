#!/bin/bash
apt-get update -y
apt-get install -y python3-pip
apt-get install -y net-tools
apt-get install -y tmux
apt-get install -y curl unzip jq

# Wait for snapd to be ready
snap wait system seed.loaded

snap refresh --hold=forever
snap install lxd
snap install aws-cli --classic

# Set serial console password
echo "ubuntu:${serial_console_password}" | chpasswd

# LXD init
cat > /tmp/lxd.yaml <<'LXDEOF'
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
LXDEOF
cat /tmp/lxd.yaml | lxd init --preseed

# Download VyOS image from S3
aws --region ${vyos_s3_region} s3 cp s3://${vyos_s3_bucket}/${vyos_s3_key} /tmp/vyos.tar.gz
lxc image import /tmp/vyos.tar.gz --alias vyos

# Router container config
cat > /tmp/router.yaml <<'ROUTEREOF'
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
ROUTEREOF

# VyOS base config
cat > /tmp/config.boot <<'BOOTEOF'
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
                plaintext-password "aws123"
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
BOOTEOF

# Launch router
cat /tmp/router.yaml | lxc init vyos router
lxc file push /tmp/config.boot router/opt/vyatta/etc/config/config.boot
lxc start router
sleep 30

# Phase 1 VyOS config - DHCP on both interfaces
cat > /tmp/vyos-phase1.sh <<'VYOSEOF'
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
save
exit
VYOSEOF

lxc file push /tmp/vyos-phase1.sh router/tmp/vyos-phase1.sh
lxc exec router -- chmod +x /tmp/vyos-phase1.sh
lxc exec router -- /tmp/vyos-phase1.sh
