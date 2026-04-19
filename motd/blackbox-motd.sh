#!/usr/bin/env bash
# BLACKBOX MOTD — displayed on SSH login

UPTIME=$(uptime -p 2>/dev/null || echo "unknown")
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "unknown")
MEMORY=$(free -h 2>/dev/null | awk '/Mem:/{printf "%s / %s", $3, $2}' || echo "unknown")
DOCKER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

cat << 'ART'

  ____  _        _    ____ _  ______   _____  __
 | __ )| |      / \  / ___| |/ / __ ) / _ \ \/ /
 |  _ \| |     / _ \| |   | ' /|  _ \| | | \  /
 | |_) | |___ / ___ \ |___| . \| |_) | |_| /  \
 |____/|_____/_/   \_\____|_|\_\____/ \___/_/\_\

ART

echo "  Host:       $(hostname)"
echo "  IP:         ${IP}"
echo "  Uptime:     ${UPTIME}"
echo "  Load:       ${LOAD}"
echo "  Memory:     ${MEMORY}"
echo "  Containers: ${DOCKER_COUNT} running"
echo ""
