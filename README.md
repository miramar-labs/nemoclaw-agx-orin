# Installing NemoClaw on Orin AGX

NemoClaw is an open-source reference stack that runs OpenClaw agents inside a secure NVIDIA OpenShell sandbox. It launched at GTC 2026 and is currently in early preview — not yet production-ready. GitHub
The standard one-liner installer works on desktop Linux but hits three Orin-specific issues you need to fix first.

## Known Orin Issues

**Problem 1** — iptables nf_tables not supported: The OpenShell cluster image defaults to iptables v1.8.10 (nf_tables), but the Tegra 5.15 kernel lacks full nf_tables support, causing k3s inside the container to panic with RULE_INSERT failed (No such file or directory). NVIDIA Developer Forums

**Problem 2** — br_netfilter not loaded: Without br_netfilter, bridged pod-to-pod traffic bypasses iptables, breaking Kubernetes DNS resolution. The sandbox crashes with failed to connect to OpenShell server: dns error: Temporary failure in name resolution. NVIDIA Developer Forums

**Problem 3** — Ollama listens on 127.0.0.1 only: If using local Ollama for inference, it defaults to 127.0.0.1:11434, which is unreachable from inside the OpenShell sandbox container. Onboarding fails at step [5/7]. NVIDIA Developer Forums
There is also a known GPU detection bug: the NemoClaw GPU detection logic only checks for "GB10" (Grace Blackwell) chip names, so on Orin, where nvidia-smi --query-gpu=memory.total returns [N/A] due to unified memory architecture, it incorrectly reports "No GPU detected" and falls back to cloud inference. GitHub A fix has been filed upstream (GitHub issue #300).

## Prerequisites

### Install Docker:

    sudo apt-get remove docker docker-engine docker.io containerd runc
    sudo apt-get update && sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

### Install NVIDIA Container Toolkit:

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker

### Add your user to the docker group:

    sudo usermod -aG docker $USER && newgrp docker

### Set NVIDIA as the default Docker runtime — edit /etc/docker/daemon.json:

    {
        "runtimes": {
            "nvidia": {
                "path": "nvidia-container-runtime",
                "runtimeArgs": []
            }
        },
        "default-runtime": "nvidia"
    }

Then:

    sudo systemctl restart docker


## Pre-Install Fixes

### Step 1 — Load br_netfilter:

    sudo modprobe br_netfilter
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

    # Make persistent across reboots:
    echo br_netfilter | sudo tee /etc/modules-load.d/k8s.conf
    echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee /etc/sysctl.d/k8s.conf

### Step 2 — Patch the cluster image to use iptables-legacy:

    IMAGE_NAME="ghcr.io/nvidia/openshell/cluster:0.0.13"

    docker run --entrypoint sh --name fix-iptables "$IMAGE_NAME" -c '
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables
    ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables
    iptables --version
    '

    docker commit \
    --change 'ENTRYPOINT ["/usr/local/bin/cluster-entrypoint.sh"]' \
    fix-iptables "$IMAGE_NAME"

    docker rm fix-iptables

### Step 3 — Configure Ollama to listen on all interfaces

    sudo mkdir -p /etc/systemd/system/ollama.service.d
    echo -e '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"' \
    | sudo tee /etc/systemd/system/ollama.service.d/override.conf
    sudo systemctl daemon-reload && sudo systemctl restart ollama

    # Verify:
    ss -tlnp | grep 11434  # Should show 0.0.0.0:11434

### Step 4 - Update Ollama

    curl -fsSL https://ollama.com/install.sh | sh

## Install NemoClaw

    curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash

During onboarding you'll be prompted for a sandbox name (accept the default my-assistant), an inference option (choose 2 for local Ollama), and an Ollama model. The Docker image build at step [3/7] takes about 10 minutes on Orin on first run due to no cache.

### Verify

After install, the dashboard should be at http://127.0.0.1:18789/ and the OpenShell gateway at https://127.0.0.1:8080.

### Connect to your sandbox:

    nemoclaw my-assistant connect

### Check sandbox health:

    docker exec openshell-cluster-nemoclaw kubectl get pods -n openshell

### Memory Note

The sandbox image is approximately 2.4 GB compressed. On machines with less than 8 GB of RAM, the Docker daemon, k3s, and the OpenShell gateway running together can trigger the OOM killer. If you can't add memory, configuring at least 8 GB of swap can work around this at the cost of slower performance.

### Choosing a model (for 64GB Orin)

Best starting point for NemoClaw:

    ollama pull gpt-oss:20b

This is the sweet spot for the 64 GB Orin — it's NVIDIA's own open model, purpose-built for agentic tasks, and fits comfortably in your memory. You'll get around 33–34 tokens/sec which is solid for an always-on assistant.
If gpt-oss:20b feels slow or you want something snappier, drop down to qwen3:14b or llama3.1:8b. And if you just want to smoke-test the NemoClaw setup first before pulling a 13 GB model, grab qwen3.5:2b — it's tiny and fast.

## Optional

### Install Claude Code

### Install Obsidian
