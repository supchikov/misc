#!/bin/bash
# Скрипт для конфигурации iptables для OpenVPN сервера и клиента.  
# Меняем переменные WAN, WAN_IP, LAN, LAN_IP_RANGE на нужные.
# Объявление переменных
export IPT="iptables"

# Интерфейс который смотрит в интернет
export WAN=eth0
export WAN_IP=88.222.222.222

# Локалка
export LAN=eth1
export LAN_IP_RANGE=192.168.100.0/24

# Очистка всех цепочек iptables
$IPT -F
$IPT -F -t nat
$IPT -F -t mangle
$IPT -X
$IPT -t nat -X
$IPT -t mangle -X

# Установим политики по умолчанию для трафика, не соответствующего ни одному из правил
$IPT -P INPUT DROP
$IPT -P OUTPUT DROP
$IPT -P FORWARD DROP

# разрешаем трафик для loopback и локалки
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A OUTPUT -o lo -j ACCEPT
$IPT -A INPUT -i $LAN -j ACCEPT
$IPT -A OUTPUT -o $LAN -j ACCEPT

# разрешаем пинги
$IPT -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
$IPT -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
$IPT -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
$IPT -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Разрешаем исходящие соединения самого сервера
$IPT -A OUTPUT -o $WAN -j ACCEPT

# Разрешаем OpenVPN
$IPT -A INPUT -i tun+ -j ACCEPT
$IPT -A OUTPUT -o tun+ -j ACCEPT
$IPT -A FORWARD -i tun+ -j ACCEPT
# Разрешаем доступ из внутренней сети в vpn
$IPT -A FORWARD -i $LAN -o tun+ -j ACCEPT

# Разрешаем доступ из внутренней сети наружу
$IPT -A FORWARD -i $LAN -o $WAN -j ACCEPT

# Маскарадинг
$IPT -t nat -A POSTROUTING -o tun0 -j MASQUERADE
$IPT -t nat -A POSTROUTING -o $WAN -s $LAN_IP_RANGE -j MASQUERADE

# Состояние ESTABLISHED говорит о том, что это не первый пакет в соединении.
# Пропускать все уже инициированные соединения, а также дочерние от них
$IPT -A INPUT -p all -m state --state ESTABLISHED,RELATED -j ACCEPT
# Пропускать новые, а так же уже инициированные и их дочерние соединения
$IPT -A OUTPUT -p all -m state --state ESTABLISHED,RELATED -j ACCEPT
# Разрешить форвардинг для уже инициированных и их дочерних соединений
$IPT -A FORWARD -p all -m state --state ESTABLISHED,RELATED -j ACCEPT

# Включаем фрагментацию пакетов. Необходимо из за разных значений MTU
$IPT -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Отбрасывать все пакеты, которые не могут быть идентифицированы
# и поэтому не могут иметь определенного статуса.
$IPT -A INPUT -m state --state INVALID -j DROP
$IPT -A FORWARD -m state --state INVALID -j DROP

# Приводит к связыванию системных ресурсов, так что реальный
# обмен данными становится не возможным.
$IPT -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
$IPT -A OUTPUT -p tcp ! --syn -m state --state NEW -j DROP

# Открываем порт для ssh
$IPT -A INPUT -i $WAN -p tcp --dport 22 -j ACCEPT

# Открываем порт для openvpn
$IPT -A INPUT -i $WAN -p udp --dport 13555 -j ACCEPT

# Записываем правила
/sbin/iptables-save > /etc/sysconfig/iptables