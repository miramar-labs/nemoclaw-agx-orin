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


### Installing

    ./nemoclaw-install.sh

### Un-Installing

    ./nemoclaw-undo.sh
    

### Choosing a model (for 64GB Orin)

Best starting point for NemoClaw:

    ollama pull gpt-oss:20b

This is the sweet spot for the 64 GB Orin — it's NVIDIA's own open model, purpose-built for agentic tasks, and fits comfortably in your memory. You'll get around 33–34 tokens/sec which is solid for an always-on assistant.
If gpt-oss:20b feels slow or you want something snappier, drop down to qwen3:14b or llama3.1:8b. And if you just want to smoke-test the NemoClaw setup first before pulling a 13 GB model, grab qwen3.5:2b — it's tiny and fast.


