# Install Proxmox on a laptop

While some tutorials out there are more focused on reusing old laptops as
servers, this is more for people like me who want to use Proxmox as a Desktop
Virtualization in a Mobile Workstation, in my case, I use it to test
it-infrastructure that later can be deployed in real machines.

Follow the [official installation
instructions](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_Buster),
except those steps related to networking, since the network requires a different
configuration to let it work with a dynamic network environment, which is
typical in a laptop: dynamic IPs, different WIFIs, etc.

So far, the best network configuration I tested is via a single public IP
address via Masquerading (NAT) with iptables. See
[this](https://pve.proxmox.com/wiki/Network_Configuration) for more details.

We want that the virtual machines work properly in the internal NAT network,
with its own DCHP+DNS server. We should also consider that most of the times the
LAN we connect the laptop to offers a DNS service like dnsmasq to provide the
hostnames of the LAN.  To let our settings consider those situations we will
setup a dhcp+dns server as an LXC container, and in the laptop, we will replace
systemd-resolved by unbound.  Both the DNS service for the virtual machines and
unbound should not be installed on the laptop directly, since they share the
same port (53), in any case is better to keep them separated and not to force to
be all together. See
[this](https://www.sidn.nl/en/news-and-blogs/evaluation-of-validating-resolvers-on-linux-unbound-and-knot-resolver-recommended)
for more reasons to replace dnsmasq and systemd-resolved.

In the following instructions, we call _dhcpdns_ the LXC container,
_mydomain.local_ the local domain and _mylaptop_ the laptop hostname:

- Install the package bind-utils:
  ```
  sudo apt install bind-utils
  ```

- Edit the file /etc/network/interfaces and create a bridge:

  ```
  auto vmbr0
  iface vmbr0 inet static
        address  10.8.0.1
        netmask  255.255.255.0
        dns-nameservers 10.8.0.2
        dns-search mydomain.local
        hwaddress ether fe:1e:1f:96:a2:8f
        bridge_ports none
        bridge_stp off
        bridge_fd 0
        post-up echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '10.8.0.0/24' -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '10.8.0.0/24' -j MASQUERADE
  ```
  
  Here we are assuming that the host IP is 10.8.0.1.  hwaddress is a random
  address that we fix beforehand, you can get one by commenting out such line,
  restarting the network and copy-paste the generated one. Note that we called
  iptables without the -o option, that is to avoid problems when using external
  network adapters.

- When editing the /etc/hosts file, use the laptop IP address in the internal
  NAT network, for instance:

  ```
  10.8.0.1	mylaptop.mydomain.local mylaptop
  ```

- After installing Proxmox, create a Debian LXC container, it will be the
  dhcp+dns server.

- I decided to install isc-dhcp-server+bind9 instead of dnsmasq, since it offers
  a more comprehensible set of features and is more stable.  Follow
  [this](https://talk-about-it.ca/setup-bind9-with-isc-dhcp-server-dynamic-host-registration/)
  tutorial to setup it with dynamic host registration. Without more details,
  since they are covered in such link, these are the configuration files you can
  follow as examples:

  - /etc/dhcp/dhcpd.conf:

    ```
    authoritative;
    default-lease-time    14400;
    max-lease-time        18000;
    log-facility          local7;

    ddns-domainname "mydomain.local.";
    ddns-rev-domainname "in-addr.arpa.";
    ddns-update-style interim;
    ignore client-updates;
    update-static-leases on;
    use-host-decl-names on;
    option domain-name "mydomain.local.";
    include "/etc/dhcp/rndc.key";
    update-optimization off;
    update-conflict-detection off;

    zone mydomain.local. {
            primary 10.8.0.2;
            key rndc-key;
    }

    zone 8.10.in-addr.arpa. {
            primary 10.8.0.2;
            key rndc-key;
    }

    subnet 10.8.0.0 netmask 255.255.255.0 {
      range                      10.8.0.20 10.8.0.99;
      option subnet-mask         255.255.255.0;
      option routers             10.8.0.1;
      option domain-name-servers 10.8.0.2;

      host mylaptop {
        hardware ethernet fe:1e:1f:96:a2:8f;
        fixed-address 10.8.0.1;
      }
      host dhcpdns {
        hardware ethernet e6:71:ec:3e:f9:3b;
        fixed-address dhcpdns;
      }
    }
    ```

  - /etc/bind/named.conf.local:

    ```
    include "/etc/bind/rndc.key";
    
    zone "mydomain.local" {
      type master;
      file "/etc/bind/zones/mydomain.local";
      allow-update { key rndc-key; };
    };
    zone "8.10.in-addr.arpa" {
      type master;
      notify no;
      file "/etc/bind/zones/8.10.in-addr.arpa";
      allow-update { key rndc-key; };
    };
    
    ```

  - /etc/bind/named.conf.options:
    ```
    options {
            directory "/var/cache/bind";
            query-source address * port *;
    
            forwarders {
              // using OpenDNS, but you can use others:
              208.67.222.222;
              208.67.220.220;
            };
    
            dnssec-validation auto;
            auth-nxdomain no;
            listen-on-v6 { none; };
            listen-on { 127.0.0.1; 10.8.0.2; };
            allow-transfer { none; };
            allow-recursion { internals; };
            version none;
    };
    ```

  - /etc/bind/zones/mydomain.local:
    ```
    $ORIGIN .
    $TTL 604800         ; 1 week
    mydomain.local                IN SOA        mydomain.local. root.mydomain.local. (
                                    635        ; serial
                                    604800     ; refresh (1 week)
                                    86400      ; retry (1 day)
                                    2419200    ; expire (4 weeks)
                                    604800     ; minimum (1 week)
                                    )
                            NS       mydomain.local.
                            NS       localhost.
                            A        10.8.0.2
    $ORIGIN mydomain.local.
    ```
    
  - /etc/bind/zones/8.10.in-addr.arpa:
    ```
    $ORIGIN .
    $TTL 604800     ; 1 week
    8.10.in-addr.arpa        IN SOA        mydomain.local. root.mydomain.local. (
                                    23         ; serial
                                    604800     ; refresh (1 week)
                                    86400      ; retry (1 day)
                                    2419200    ; expire (4 weeks)
                                    604800     ; minimum (1 week)
                                    )
                            NS       dhcpdns.
                            A        10.8.0.2
    $ORIGIN 0.8.10.in-addr.arpa.
    ```

  - Don't forget:
    ```
    sudo ln -s /etc/bind/rndc.key /etc/dhcp/rndc.key
    ```

- On the laptop, install unbound and set it to replace systemd-resolved
  ```
  sudo apt remove connman # this was interfering with unbound in Proxmox 7/Debian bullseye
  sudo apt install unbound
  sudo systemctl disable systemd-resolved
  sudo systemctl stop systemd-resolved
  sudo systemctl enable unbound-resolvconf
  sudo systemctl enable unbound
  ```
  - If you use NetworkManager, open as root the file /etc/NetworkManager/NetworkManager.conf and below [main]
    put this line:
    ```
    dns=unbound
    ```
  - Add the next lines to /etc/unbound/unbound.conf:
    ```
    server:
        cache-max-ttl: 3600
        domain-insecure: "local"
        domain-insecure: "mydomain.local"
    ```
    domain-insecure are the (unsigned) internal domains you are using.

  - Install openresolv:

    ```
    apt install openresolv
    ```
    
  - In /etc/resolvconf.conf, modify the unbound_conf line to:
    ```
    unbound_conf=/etc/unbound/unbound.conf.d/resolvconf_resolvers.conf
    ```
    We should use such directory, otherwise apparmor will complain when starting
    the unbound service.
    ```
    sudo service unbound restart
    ```
    
  - Although not recommended, if you have problems with some internet services
    (reddit, zoom, etc.), you can try disabling dnssec, to do that open the file
    /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf and comment-out
    the option auto-trust-anchor-file. Read
    [this](https://www.nlnetlabs.nl/documentation/unbound/howto-turnoff-dnssec/)
    for more details.

  - Add the IP of the host on the dynamic dns, on the LXC container:
    ```
    nsupdate -k /etc/bind/rndc.key
    > server 10.8.0.2
    > update delete mylaptop.mydomain.local. A
    > send
    > update add mylaptop.mydomain.local. 315576000 A 10.8.0.1
    > send
    > quit
    ```
    315576000 means 10 years, a work around to set it as a static IP

  - On laptops with NVidia GPUs, if you don't plan to PCI-pass-through it, you
    would like to enable it.  It was disabled on proxmox in favor of the nouveau
    driver, but on my hp spectre 320, the nouveau driver was causing a crash.
    See https://bugzilla.proxmox.com/show_bug.cgi?id=701 for more details,
    according to it that was blocked due to a bug in kernel 4.1.3-1, but
    currently we use kernels newer than 5.10, so it should not cause a problem
    anymore.

  - comment out 'blacklist nvidiafm' from /etc/modprobe.d/pve-blacklist.conf

  - sudo apt install pve-headers
    sudo apt install nvidia-drivers
    sudo modprobe nvidia

    to check if everything is Ok:

    nvidia-settings
    nvidia-smi
    lsmod|grep nvidia
