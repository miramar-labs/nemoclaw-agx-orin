# Installing NemoClaw on Orin AGX

[NemoClaw Docs](https://docs.nvidia.com/nemoclaw/latest/index.html)

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

Several Nemotron models run on the AGX Orin 64GB. Here's what fits and what doesn't:

✅ Will run well:
| Model | Pull Command | Size | Notes |
|---|---|---|---|
| **nemotron-3-nano:4b** | `ollama pull nemotron-3-nano:4b` | 2.8 GB | Fastest Nemotron, good for quick agentic tasks |
| **nemotron-3-nano:30b** | `ollama pull nemotron-3-nano:30b` | 24 GB | ⭐ Best Nemotron for Orin — MoE, only activates ~3B params per token, 1M context |
| **nemotron-3-nano:30b-a3b-q8_0** | `ollama pull nemotron-3-nano:30b-a3b-q8_0` | 34 GB | Higher quality quant of the 30B |
| **nemotron-mini:4b** | `ollama pull nemotron-mini:4b-instruct-q4_K_M` | ~3 GB | Older Nemotron, decent tool use |
| **gpt-oss:20b** | `ollama pull gpt-oss:20b` | 13 GB | ⭐ NVIDIA's recommended model for Orin, ~34 tok/s |
| **llama3.1:8b** | `ollama pull llama3.1:8b` | 4.9 GB | Fast general assistant |
| **llama3.1:70b-q4_K_M** | `ollama pull llama3.1:70b-q4_K_M` | ~40 GB | Largest Llama that fits comfortably |
| **qwen3:14b** | `ollama pull qwen3:14b` | 9 GB | Strong reasoning and tool use |
| **qwen3:30b-a3b** | `ollama pull qwen3:30b-a3b` | 19 GB | MoE, efficient, great for agents |
| **gemma3:12b** | `ollama pull gemma3:12b` | 8 GB | Good general assistant, fast |
| **gemma3:27b** | `ollama pull gemma3:27b` | 17 GB | Best Gemma quality on Orin |
| **mistral:7b** | `ollama pull mistral:7b` | 4.1 GB | Reliable, fast, good instruction following |
| **phi4:14b** | `ollama pull phi4:14b` | 9 GB | Microsoft, strong reasoning for its size |
| **deepseek-r1:14b** | `ollama pull deepseek-r1:14b` | 9 GB | Good reasoning/thinking model |
| **deepseek-r1:32b** | `ollama pull deepseek-r1:32b` | 20 GB | Better reasoning, still fits well |
| **nemotron-3-nano:30b-a3b-fp16** | `ollama pull nemotron-3-nano:30b-a3b-fp16` | 63 GB | ⚠️ Technically fits but leaves almost no headroom |
| **nemotron-3-super** | `ollama pull nemotron-3-super` | ~87 GB | ❌ Too large — needs AGX Thor (128GB) |

Best pick for NemoClaw on your Orin:

    ollama pull gpt-oss:20b


Example of switching inference model:

    ./nemoclaw-restart.sh
    nemoclaw onboard  (pick the model here & create sandbox)
    openclaw tui
    

Install jtop to monitor GPU:

    sudo pip3 install jetson-stats --break-system-packages
    sudo systemctl restart jtop
    jtop

In nemoclaw ask a question:

    what are the specs of this machine

Gracefull shutdown

    nemoclaw my-assistant destroy
    openshell gateway destroy --name nemoclaw

That cleanly removes the sandbox and stops the gateway. To bring it back up later just run:

    ~/nemoclaw-restart.sh.