#!/bin/bash
set -e
echo "=== Restarting NemoClaw ==="

# Ensure Docker is running
sudo systemctl start docker
for i in $(seq 1 30); do
    docker info &>/dev/null && break
    echo "Waiting for Docker... ($i/30)"
    sleep 2
done
docker info &>/dev/null || { echo "ERROR: Docker failed to start"; exit 1; }

# Destroy gateway
openshell gateway destroy --name nemoclaw 2>/dev/null || true

# Pull cluster image if missing
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q 'openshell/cluster:0.0.13'; then
    echo "Pulling cluster image..."
    docker pull ghcr.io/nvidia/openshell/cluster:0.0.13
fi

# Patch ALL openshell-related images
for IMAGE in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'openshell|sandbox-from|sandbox-base'); do
    echo "Patching $IMAGE..."
    mkdir -p /tmp/openshell-patch
    cat > /tmp/openshell-patch/Dockerfile << EOF
FROM $IMAGE
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true \
 && update-alternatives --set iptables-restore /usr/sbin/iptables-legacy-restore 2>/dev/null || true \
 && update-alternatives --set ip6tables-restore /usr/sbin/ip6tables-legacy-restore 2>/dev/null || true \
 && ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables \
 && ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables \
 && ln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore 2>/dev/null || true \
 && ln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore 2>/dev/null || true
RUN printf '#!/bin/sh\nln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables\nln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables\nln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore 2>/dev/null || true\nln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore 2>/dev/null || true\nexec /usr/local/bin/cluster-entrypoint.sh "\$@"\n' > /usr/local/bin/jetson-entrypoint.sh && chmod +x /usr/local/bin/jetson-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/jetson-entrypoint.sh"]
EOF
    docker build --no-cache -t "$IMAGE" /tmp/openshell-patch/ && echo "✓ Patched $IMAGE" || echo "✗ Failed $IMAGE"
done

# Start gateway
openshell gateway start --name nemoclaw

# Connect if sandbox exists, otherwise prompt onboard
if nemoclaw my-assistant status &>/dev/null; then
    nemoclaw my-assistant connect
else
    echo ""
    echo "No sandbox found. Run: nemoclaw onboard"
    echo "After onboard completes run: ~/nemoclaw-restart.sh"
fi
