#!/bin/bash
echo "=== Undoing everything ==="

sudo systemctl stop openshell-gateway.service 2>/dev/null || true
sudo systemctl disable openshell-gateway.service 2>/dev/null || true
sudo systemctl stop openshell-iptables-patch.service 2>/dev/null || true
sudo systemctl disable openshell-iptables-patch.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/openshell-gateway.service
sudo rm -f /etc/systemd/system/openshell-iptables-patch.service
sudo systemctl daemon-reload

sudo rm -f /usr/local/bin/patch-openshell-iptables.sh
sudo rm -f /usr/local/bin/nemoclaw-onboard.sh
sudo rm -f /usr/local/bin/nemoclaw-wrapper.sh

curl -fsSL https://raw.githubusercontent.com/NVIDIA/NemoClaw/refs/heads/main/uninstall.sh | bash -s -- --yes 2>/dev/null || true
sudo npm uninstall -g nemoclaw 2>/dev/null || true

docker rm -f $(docker ps -aq --filter "name=openshell") 2>/dev/null || true
docker rm -f $(docker ps -aq --filter "name=fix-iptables") 2>/dev/null || true
docker rmi -f $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'openshell|nemoclaw|sandbox-from|sandbox-base') 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

rm -f ~/.local/bin/openshell
rm -f ~/.local/bin/openshell-0.0.16.bak

# NOTE: iptables left as legacy — Docker on Orin requires it
# sudo update-alternatives --set iptables /usr/sbin/iptables-nft

sudo rm -f /etc/modules-load.d/k8s.conf
sudo rm -f /etc/modules-load.d/k8s-iptables.conf
sudo rm -f /etc/modules-load.d/iptables-legacy.conf
sudo rm -f /etc/sysctl.d/k8s.conf

sudo rm -f /etc/systemd/system/ollama.service.d/override.conf
sudo rmdir /etc/systemd/system/ollama.service.d 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl restart ollama 2>/dev/null || true

rm -rf ~/openshell-src

sed -i "/alias nemoclaw=/d" ~/.zshrc

echo "=== Done. Now reboot: sudo reboot ==="
