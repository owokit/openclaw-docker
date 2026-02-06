FROM ubuntu:24.04

# 容器级默认变量：
# - OPENCLAW_HOME：非 root 用户的 OpenClaw 运行配置目录。
# - OPENCLAW_PORT：gateway 监听端口，可通过 -e OPENCLAW_PORT=xxxx 在运行时覆盖。
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    OPENCLAW_HOME=/home/node/.openclaw \
    GH_CONFIG_DIR=/home/node/.openclaw/gh \
    OPENCLAW_PORT=18789

ARG OPENCLAW_VERSION=latest
ARG NODE_MAJOR=24

# 使用 Ubuntu 24.04（最新 LTS）并通过 apt 安装基础工具链。
# Ubuntu 官方源的 nodejs 版本通常偏旧，改用 NodeSource 安装 Node.js LTS。
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      git-lfs \
      gh \
      awscli \
      python3.13 \
      python3.13-venv \
      nodejs && \
    rm -rf /var/lib/apt/lists/*

# 全局安装 OpenClaw CLI，并配置 python/pip 运行时。
RUN git lfs install --system && \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && \
    python3.13 /tmp/get-pip.py && \
    rm -f /tmp/get-pip.py && \
    python3.13 -m pip install --no-cache-dir boto3 && \
    ln -sf /usr/bin/python3.13 /usr/local/bin/python3 && \
    ln -sf /usr/bin/python3.13 /usr/local/bin/python && \
    npm install -g --omit=dev --no-audit "openclaw@${OPENCLAW_VERSION}" && \
    npm cache clean --force

# 创建非 root 用户，提升运行安全性。
RUN useradd -m -u 1000 -s /usr/sbin/nologin node && \
    mkdir -p "${OPENCLAW_HOME}" && \
    chown -R node:node /home/node && \
    chmod 700 "${OPENCLAW_HOME}"

# 启动脚本会自动应用你要求的 OpenClaw 默认配置与可选 Discord allowlist JSON，
# 若未传入自定义命令，则默认启动 `openclaw gateway`。
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/openclaw-entrypoint.sh

WORKDIR /workspace
USER node

# OpenClaw 官方 Docker 文档默认 gateway 端口为 18789。
EXPOSE 18789

# 基础健康检查：检查本地 gateway 端口是否可连通。
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python3.13 -c "import os,socket; s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1', int(os.getenv('OPENCLAW_PORT','18789')))); s.close()" || exit 1

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]
CMD []
