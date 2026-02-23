interfaces {
    ethernet eth0 {
        address dhcp
        description OUTSIDE
        dhcp-options {
            default-route-distance 10
        }
    }
    ethernet eth1 {
        address dhcp
        description INSIDE
        dhcp-options {
            no-default-route
        }
    }
    loopback lo {
        address 10.255.0.1/32
    }
    vti vti0 {
        address 169.254.100.1/30
    }
    vti vti1 {
        address 169.254.100.5/30
    }
    vti vti2 {
        address 169.254.100.9/30
    }
}
protocols {
    bgp 65001 {
        neighbor 169.254.100.2 {
            ebgp-multihop 2
            remote-as 65002
            update-source 169.254.100.1
        }
        neighbor 169.254.100.6 {
            ebgp-multihop 2
            remote-as 65002
            update-source 169.254.100.5
        }
        neighbor 169.254.100.10 {
            ebgp-multihop 2
            remote-as 65001
            update-source 169.254.100.9
        }
        parameters {
            router-id 10.255.0.1
        }
    }
}
system {
    config-management {
        commit-revisions 100
         }
    host-name vyos
    login {
        user vyos {
            authentication {
                encrypted-password ****************
            }
        }
    }
    name-server eth0
    name-server eth1
    syslog {
        global {
            facility all {
                level info
            }
        }
    }
}
vpn {
    ipsec {
        esp-group ESP-GROUP {
            compression disable
            lifetime 3600
            mode tunnel
            pfs dh-group14
            proposal 1 {
                encryption aes256
                hash sha256
            }
        }
        ike-group IKE-GROUP {
            key-exchange ikev2
            lifetime 28800
            proposal 1 {
                dh-group 14
                encryption aes256
                hash sha256
            }
        }
        site-to-site {
            peer 3.120.164.246 {
                authentication {
                    mode pre-shared-secret
                    pre-shared-secret ****************
                    remote-id 10.200.2.11
                }
                connection-type initiate
                ike-group IKE-GROUP
                local-address 10.201.2.52
                vti {
                    bind vti2
                    esp-group ESP-GROUP
                         lifetime 28800
            proposal 1 {
                dh-group 14
                encryption aes256
                hash sha256
            }
        }
        site-to-site {
            peer 3.120.164.246 {
                authentication {
                    mode pre-shared-secret
                    pre-shared-secret ****************
                    remote-id 10.200.2.11
                }
                connection-type initiate
                ike-group IKE-GROUP
                local-address 10.201.2.52
                vti {
                    bind vti2
                    esp-group ESP-GROUP
                }
            }
            peer 54.84.125.217 {
                authentication {
                    mode pre-shared-secret
                    pre-shared-secret ****************
                    remote-id 10.30.2.197
                }
                connection-type initiate
                ike-group IKE-GROUP
                local-address 10.201.2.52
                vti {
                    bind vti1
                    esp-group ESP-GROUP
                }
            }
            peer 54.237.194.170 {
                authentication {
                    mode pre-shared-secret
                    pre-shared-secret ****************
                    remote-id 10.20.2.249
                }
                connection-type initiate
                ike-group IKE-GROUP
                local-address 10.201.2.52
                vti {
                    bind vti0
                    esp-group ESP-GROUP
                }
            }
        }
    }
}