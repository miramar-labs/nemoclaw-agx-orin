#!/bin/bash
set -e
echo "=== NemoClaw Orin Install ==="

# ── 0. Host iptables-legacy (required for Docker on Orin) ─────────
echo "[0/8] Setting host iptables to legacy..."
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# ── 1. Docker ─────────────────────────────────────────────────────
echo "[1/8] Ensuring Docker is running..."
sudo systemctl enable docker
sudo systemctl start docker
for i in $(seq 1 30); do
    docker info &>/dev/null && break
    echo "Waiting for Docker... ($i/30)"
    sleep 2
done
docker info &>/dev/null || { echo "ERROR: Docker failed to start"; exit 1; }

# ── 2. Kernel modules ─────────────────────────────────────────────
echo "[2/8] Kernel modules..."
sudo modprobe br_netfilter ip_tables iptable_filter iptable_nat
cat << 'EOF' | sudo tee /etc/modules-load.d/k8s-iptables.conf
br_netfilter
ip_tables
iptable_filter
iptable_nat
EOF
cat << 'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

# ── 3. Pin openshell to 0.0.13 ────────────────────────────────────
echo "[3/8] Installing openshell 0.0.13..."
ARCH=$(uname -m)
wget -q "https://github.com/NVIDIA/OpenShell/releases/download/v0.0.13/openshell-${ARCH}-unknown-linux-musl.tar.gz" \
    -O /tmp/openshell.tar.gz
tar xzf /tmp/openshell.tar.gz -C /tmp
install -m 755 /tmp/openshell ~/.local/bin/openshell
echo "openshell: $(openshell --version)"

# ── 4. Pull, patch and pin cluster image ──────────────────────────
echo "[4/8] Building patched cluster image..."
docker pull ghcr.io/nvidia/openshell/cluster:0.0.13
mkdir -p /tmp/openshell-patch
cat << 'EOF' > /tmp/openshell-patch/Dockerfile
FROM ghcr.io/nvidia/openshell/cluster:0.0.13
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true \
 && update-alternatives --set iptables-restore /usr/sbin/iptables-legacy-restore 2>/dev/null || true \
 && update-alternatives --set ip6tables-restore /usr/sbin/ip6tables-legacy-restore 2>/dev/null || true \
 && ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables \
 && ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables \
 && ln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore 2>/dev/null || true \
 && ln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore 2>/dev/null || true
RUN printf '#!/bin/sh\nln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables\nln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables\nln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore 2>/dev/null || true\nln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore 2>/dev/null || true\nexec /usr/local/bin/cluster-entrypoint.sh "$@"\n' \
    > /usr/local/bin/jetson-entrypoint.sh && chmod +x /usr/local/bin/jetson-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/jetson-entrypoint.sh"]
EOF
docker build --no-cache -t ghcr.io/nvidia/openshell/cluster:0.0.13 /tmp/openshell-patch/
docker rmi $(docker images --format '{{.Repository}}@{{.Digest}}' | grep 'openshell/cluster') 2>/dev/null || true
echo "✓ Cluster image patched and pinned"

# ── 5. Ollama on 0.0.0.0 ──────────────────────────────────────────
echo "[5/8] Configuring Ollama..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat << 'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama 2>/dev/null || true

# ── 6. Boot service ───────────────────────────────────────────────
echo "[6/8] Installing boot service..."
OPENSHELL_BIN=$(which openshell)
sudo tee /etc/systemd/system/openshell-gateway.service << EOF
[Unit]
Description=OpenShell Gateway
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
ExecStart=${OPENSHELL_BIN} gateway start --name nemoclaw
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable openshell-gateway.service

# ── 7. Install NemoClaw ───────────────────────────────────────────
echo "[7/8] Installing NemoClaw..."
echo ""
echo ">>> IMPORTANT: press ENTER for default sandbox name 'my-assistant'"
echo ">>> Choose local Ollama for inference"
echo ""
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash

echo ""
echo "=== Install complete ==="
echo "Run: nemoclaw-up.sh"
