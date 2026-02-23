interfaces {
    ethernet eth0 {
        address dhcp
        description "OUTSIDE"
    }
    ethernet eth1 {
        address dhcp
        description "INSIDE"
    }
    loopback lo {
        address 10.255.0.1/32
    }
    vti vti0 {
        address 169.254.100.1/30
    }
}
system {
    host-name nv-sdwan
    login {
        user vyos {
            authentication {
                plaintext-password ""
            }
        }
    }
}
vpn {
    ipsec {
        interface eth0
        esp-group ESP-GROUP {
            compression disable
            lifetime 3600
            mode tunnel
            pfs dh-group14
            proposal 1 {
                encryption aes256gcm128
                hash sha256
            }
        }
        ike-group IKE-GROUP {
            key-exchange ikev2
            lifetime 28800
            proposal 1 {
                dh-group 14
                encryption aes256gcm128
                hash sha256
            }
        }
        site-to-site {
            peer ${remote_eip} {
                authentication {
                    mode pre-shared-secret
                    pre-shared-secret "${psk}"
                }
                connection-type initiate
                ike-group IKE-GROUP
                local-address ${local_eip}
                vti {
                    bind vti0
                    esp-group ESP-GROUP
                }
            }
        }
    }
}
protocols {
    bgp ${local_asn} {
        neighbor 169.254.100.2 {
            ebgp-multihop 2
            remote-as ${remote_asn}
            update-source 169.254.100.1
        }
        network 10.255.0.1/32 {
        }
        parameters {
            router-id 10.255.0.1
        }
    }
}
