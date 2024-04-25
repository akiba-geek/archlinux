#!/bin/sh

user=
VPN="off"

case $DEVICE_IP_IFACE in
  "lo" | "docker" | "virbr0" ) ;;
  *)
  echo "interface $DEVICE_IP_IFACE action $NM_DISPATCHER_ACTION vpn $VPN"
  case $VPN in
    "off");;
    "tor")
    ### Set variables
    # The UID that Tor runs as (varies from system to system)
    # _tor_uid="109" #As per assumption
    #_tor_uid=`id -u debian-tor` #Debian/Ubuntu
    _tor_uid=`id -u tor` #ArchLinux/Gentoo

    # Tor's TransPort
    _trans_port="9040"

    # Tor's DNSPort
    _dns_port="5353"

    # Tor's VirtualAddrNetworkIPv4
    _virt_addr="10.192.0.0/10"

    # LAN destinations that shouldn't be routed through Tor
    _non_tor="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"

    # Other IANA reserved blocks (These are not processed by tor and dropped by default)
    _resv_iana="0.0.0.0/8 100.64.0.0/10 169.254.0.0/16 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32"

    case $NM_DISPATCHER_ACTION in
      up)
      ### Check for connection
      IS_CONNECTED=0
      while [[ $IS_CONNECTED != 1 ]]; do
        while read -r line; do
          if [[ $line == *"ms" ]]; then
            IS_CONNECTED=1
            break
          fi
        done< <(ping he.net)
      done
      
      systemctl start tor.service
      while read -r line; do
        if [[ $line == *"Bootstrapped 100%"* ]]; then
          break
        fi
      done< <(journalctl -xeu tor.service --follow --since "$(date +%b\ %d\ %T)")

      ### Don't lock yourself out after the flush
      #iptables -P INPUT ACCEPT
      #iptables -P OUTPUT ACCEPT

      ### *nat PREROUTING (For middlebox)
      #iptables -t nat -A PREROUTING -d $_virt_addr -i $DEVICE_IP_IFACE -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port
      #iptables -t nat -A PREROUTING -i $DEVICE_IP_IFACE -p udp --dport 53 -j REDIRECT --to-ports $_dns_port

      # Allow lan access for hosts in $_non_tor
      for _lan in $_non_tor; do
         iptables -t nat -A PREROUTING -i $DEVICE_IP_IFACE -d $_lan -j RETURN
      done

      for _iana in $_resv_iana; do
         iptables -t nat -A PREROUTING -i $DEVICE_IP_IFACE -d $_iana -j RETURN
      done

      iptables -t nat -A PREROUTING -i $DEVICE_IP_IFACE -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      ### *nat OUTPUT (For local redirection)
      # nat .onion addresses
      iptables -t nat -A OUTPUT -d $_virt_addr -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      # nat dns requests to Tor
      iptables -t nat -A OUTPUT -d 127.0.0.1/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports $_dns_port

      # Don't nat the Tor process, the loopback, or the local network
      iptables -t nat -A OUTPUT -m owner --uid-owner $_tor_uid -j RETURN
      iptables -t nat -A OUTPUT -o lo -j RETURN

      # Allow lan access for hosts in $_non_tor
      for _lan in $_non_tor; do
        iptables -t nat -A OUTPUT -d $_lan -j RETURN
      done

      for _iana in $_resv_iana; do
        iptables -t nat -A OUTPUT -d $_iana -j RETURN
      done

      # Redirect all other pre-routing and output to Tor's TransPort
      iptables -t nat -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      ### *filter INPUT
      # Don't forget to grant yourself ssh access from remote machines before the DROP.
      #iptables -A INPUT -i $_out_if -p tcp --dport 22 -m state --state NEW -j ACCEPT

      iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
      iptables -A INPUT -i lo -j ACCEPT

      # Allow DNS lookups from connected clients and internet access through tor.
      iptables -A INPUT -d $IP4_GATEWAY -i $DEVICE_IP_IFACE -p udp -m udp --dport $_dns_port -j ACCEPT
      iptables -A INPUT -d $IP4_GATEWAY -i $DEVICE_IP_IFACE -p tcp -m tcp --dport $_trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

      # Allow INPUT from lan hosts in $_non_tor
      # Uncomment these 3 lines to enable.
      #for _lan in $_non_tor; do
      # iptables -A INPUT -s $_lan -j ACCEPT
      #done

      # Log & Drop everything else. Uncomment to enable logging.
      #iptables -A INPUT -j LOG --log-prefix "Dropped INPUT packet: " --log-level 7 --log-uid
      iptables -A INPUT -j DROP

      ### *filter FORWARD
      iptables -A FORWARD -j DROP

      ### *filter OUTPUT
      iptables -A OUTPUT -m state --state INVALID -j DROP
      iptables -A OUTPUT -m state --state ESTABLISHED -j ACCEPT

      # Allow Tor process output
      iptables -A OUTPUT -o $DEVICE_IP_IFACE -m owner --uid-owner $_tor_uid -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

      # Allow loopback output
      iptables -A OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

      # Tor transproxy magic
      iptables -A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport $_trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

      # Transparent proxy leak fix
      iptables -I OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j DROP
      iptables -I OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j DROP
 
      # Allow OUTPUT to lan hosts in $_non_tor
      # Uncomment these 3 lines to enable.
      #for _lan in $_non_tor; do
      # iptables -A OUTPUT -d $_lan -j ACCEPT
      #done

      # Log & Drop everything else. Uncomment to enable logging
      #iptables -A OUTPUT -j LOG --log-prefix "Dropped OUTPUT packet: " --log-level 7 --log-uid
      iptables -A OUTPUT -j DROP

      ### Set default policies to DROP
      iptables -P INPUT DROP
      iptables -P FORWARD DROP
      iptables -P OUTPUT DROP

      ### Set default policies to DROP for IPv6
      ip6tables -P INPUT DROP
      ip6tables -P FORWARD DROP
      ip6tables -P OUTPUT DROP

      resolvectl dns $DEVICE_IP_IFACE 127.0.0.1
      ;;
      down)
      systemctl stop tor.service
      while read -r line; do
        if [[ $(echo $line | awk '{for(i=1;i<=NF;i++) if($i=="-i") print $(i+1)}') == $DEVICE_IP_IFACE ]]; then
          IP4_GATEWAY=$(echo $line | awk '{for(i=1;i<=NF;i++) if($i=="-d") print $(i+1)}')
          break
        fi
      done< <(iptables -S)
      ### *nat PREROUTING (For middlebox)
      #iptables -t nat -D PREROUTING -d $_virt_addr -i $DEVICE_IP_IFACE -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port
      #iptables -t nat -D PREROUTING -i $DEVICE_IP_IFACE -p udp --dport 53 -j REDIRECT --to-ports $_dns_port

      # Allow lan access for hosts in $_non_tor
      for _lan in $_non_tor; do
         iptables -t nat -D PREROUTING -i $DEVICE_IP_IFACE -d $_lan -j RETURN
      done

      for _iana in $_resv_iana; do
         iptables -t nat -D PREROUTING -i $DEVICE_IP_IFACE -d $_iana -j RETURN
      done

      iptables -t nat -D PREROUTING -i $DEVICE_IP_IFACE -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      ### *nat OUTPUT (For local redirection)
      # nat .onion addresses
      iptables -t nat -D OUTPUT -d $_virt_addr -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      # nat dns requests to Tor
      iptables -t nat -D OUTPUT -d 127.0.0.1/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports $_dns_port

      # Don't nat the Tor process, the loopback, or the local network
      iptables -t nat -D OUTPUT -m owner --uid-owner $_tor_uid -j RETURN
      iptables -t nat -D OUTPUT -o lo -j RETURN

      # Allow lan access for hosts in $_non_tor
      for _lan in $_non_tor; do
        iptables -t nat -D OUTPUT -d $_lan -j RETURN
      done

      for _iana in $_resv_iana; do
        iptables -t nat -D OUTPUT -d $_iana -j RETURN
      done

      # Redirect all other pre-routing and output to Tor's TransPort
      iptables -t nat -D OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $_trans_port

      ### *filter INPUT
      # Don't forget to grant yourself ssh access from remote machines before the DROP.
      #iptables -D INPUT -i $_out_if -p tcp --dport 22 -m state --state NEW -j ACCEPT

      iptables -D INPUT -m state --state ESTABLISHED -j ACCEPT
      iptables -D INPUT -i lo -j ACCEPT
      
      # Allow DNS lookups from connected clients and internet access through tor.
      iptables -D INPUT -d $IP4_GATEWAY -i $DEVICE_IP_IFACE -p udp -m udp --dport $_dns_port -j ACCEPT
      iptables -D INPUT -d $IP4_GATEWAY -i $DEVICE_IP_IFACE -p tcp -m tcp --dport $_trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

      # Allow INPUT from lan hosts in $_non_tor
      # Uncomment these 3 lines to enable.
      #for _lan in $_non_tor; do
      # iptables -D INPUT -s $_lan -j ACCEPT
      #done

      # Log & Drop everything else. Uncomment to enable logging.
      #iptables -D INPUT -j LOG --log-prefix "Dropped INPUT packet: " --log-level 7 --log-uid
      iptables -D INPUT -j DROP

      ### *filter FORWARD
      iptables -D FORWARD -j DROP

      ### *filter OUTPUT
      iptables -D OUTPUT -m state --state INVALID -j DROP
      iptables -D OUTPUT -m state --state ESTABLISHED -j ACCEPT

      # Allow Tor process output
      iptables -D OUTPUT -o $DEVICE_IP_IFACE -m owner --uid-owner $_tor_uid -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

      # Allow loopback output
      iptables -D OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

      # Tor transproxy magic
      iptables -D OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport $_trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

      # Transparent proxy leak fix
      iptables -D OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j DROP
      iptables -D OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j DROP
 
      # Allow OUTPUT to lan hosts in $_non_tor
      # Uncomment these 3 lines to enable.
      #for _lan in $_non_tor; do
      # iptables -D OUTPUT -d $_lan -j ACCEPT
      #done

      # Log & Drop everything else. Uncomment to enable logging
      #iptables -D OUTPUT -j LOG --log-prefix "Dropped OUTPUT packet: " --log-level 7 --log-uid
      iptables -D OUTPUT -j DROP

      ### Set default policies to ACCEPT
      iptables -P INPUT ACCEPT
      iptables -P FORWARD ACCEPT
      iptables -P OUTPUT ACCEPT

      ### Set default policies to ACCEPT for IPv6
      ip6tables -P INPUT ACCEPT
      ip6tables -P FORWARD ACCEPT
      ip6tables -P OUTPUT ACCEPT

      resolvectl revert $DEVICE_IP_IFACE
      ;;
    esac
    ;;
    *)
    case $NM_DISPATCHER_ACTION in
      up)
      wg-quick up $VPN
      FWMARK=$(wg show $VPN fwmark)
      ENDPOINT=$(wg show $VPN endpoints | awk '{print $2}' | cut -d ":" -f 1)
      TABLE=$(ip rule list fwmark $FWMARK | grep -oP 'lookup \K\d+')
      ip route add $ENDPOINT via $IP4_GATEWAY dev $DEVICE_IP_IFACE
      ip -6 rule add not from all fwmark $FWMARK lookup $TABLE
      ip -6 route add default dev $VPN table $TABLE proto static scope link metric 50
      systemctl start system-novpn.slice
      mkdir -p /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/novpn.slice
      chown -R $user:$user /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/novpn.slice
      iptables -t mangle -A PREROUTING -i virbr0 -j MARK --set-mark $FWMARK
      iptables -t mangle -A OUTPUT -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MARK --set-mark $FWMARK
      iptables -t mangle -A OUTPUT -m cgroup --path "system.slice/system-novpn.slice" -j MARK --set-mark $FWMARK
      iptables -t nat -A POSTROUTING -o $DEVICE_IP_IFACE -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MASQUERADE
      iptables -t nat -A POSTROUTING -o $DEVICE_IP_IFACE -m cgroup --path "system.slice/system-novpn.slice" -j MASQUERADE
      ip6tables -t mangle -A PREROUTING -i virbr0 -j MARK --set-mark $FWMARK
      ip6tables -t mangle -A OUTPUT -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MARK --set-mark $FWMARK
      ip6tables -t mangle -A OUTPUT -m cgroup --path "system.slice/system-novpn.slice" -j MARK --set-mark $FWMARK
      ;;
      down)
      FWMARK=$(wg show $VPN fwmark)
      ENDPOINT=$(wg show $VPN endpoints | awk '{print $2}' | cut -d ":" -f 1)
      TABLE=$(ip rule list fwmark $FWMARK | grep -oP 'lookup \K\d+')
      wg-quick down $VPN
      ip -6 rule del not from all fwmark $FWMARK lookup $TABLE
      ip -6 route del default dev $VPN table $TABLE proto static scope link metric 50
      iptables -t mangle -D PREROUTING -i virbr0 -j MARK --set-mark $FWMARK
      iptables -t mangle -D OUTPUT -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MARK --set-mark $FWMARK
      iptables -t mangle -D OUTPUT -m cgroup --path "system.slice/system-novpn.slice" -j MARK --set-mark $FWMARK
      iptables -t nat -D POSTROUTING -o $DEVICE_IP_IFACE -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MASQUERADE
      iptables -t nat -D POSTROUTING -o $DEVICE_IP_IFACE -m cgroup --path "system.slice/system-novpn.slice" -j MASQUERADE
      ip6tables -t mangle -D PREROUTING -i virbr0 -j MARK --set-mark $FWMARK
      ip6tables -t mangle -D OUTPUT -m cgroup --path "user.slice/user-1000.slice/user@1000.service/novpn.slice" -j MARK --set-mark $FWMARK
      ip6tables -t mangle -D OUTPUT -m cgroup --path "system.slice/system-novpn.slice" -j MARK --set-mark $FWMARK
      ;;
    esac
    ;;
  esac
  ;;
esac
