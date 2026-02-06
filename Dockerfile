FROM public.ecr.aws/amazonlinux/amazonlinux:2023
ARG TARGETARCH

# 容器级默认变量：
# - OPENCLAW_HOME：非 root 用户的 OpenClaw 运行配置目录。
# - OPENCLAW_PORT：gateway 监听端口，可通过 -e OPENCLAW_PORT=xxxx 在运行时覆盖。
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    OPENCLAW_HOME=/home/node/.openclaw \
    OPENCLAW_PORT=18789

# 使用 dnf 安装运行时与工具链（包管理优先）：
# - nodejs24：openclaw CLI 依赖。
# - python3.13/pip：Python 运行时与 boto3 依赖。
# - git/git-lfs/awscli-2：你要求的 CI/CD 与仓库操作工具。
RUN dnf update -y && \
    dnf install -y \
      nodejs24 \
      python3.13 \
      python3.13-pip \
      curl \
      git \
      git-lfs \
      awscli-2 \
      ca-certificates \
      shadow-utils && \
    dnf clean all

# Amazon Linux 2023 官方仓库没有 gh 包，这里通过 GitHub 官方 release 安装。
RUN ARCH="${TARGETARCH:-$(uname -m)}" && \
    case "$ARCH" in \
      amd64|x86_64) GH_ARCH="linux_amd64" ;; \
      arm64|aarch64) GH_ARCH="linux_arm64" ;; \
      *) echo "不支持的架构: $ARCH" && exit 1 ;; \
    esac && \
    GH_URL="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep browser_download_url | grep "${GH_ARCH}\\.tar\\.gz" | cut -d '\"' -f 4 | head -n 1)" && \
    test -n "$GH_URL" && \
    curl -fsSL "$GH_URL" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    cp /tmp/gh_*_${GH_ARCH}/bin/gh /usr/local/bin/gh && \
    chmod +x /usr/local/bin/gh && \
    rm -rf /tmp/gh.tar.gz /tmp/gh_* && \
    gh --version

# 全局安装 OpenClaw CLI，并安装 AWS 自动化常用的 boto3。
RUN npm install -g openclaw@latest && \
    python3.13 -m pip install --no-cache-dir --upgrade pip boto3

# 统一 python/pip 命令名，避免版本差异导致命令不一致。
RUN ln -sf /usr/bin/python3.13 /usr/local/bin/python3 && \
    ln -sf /usr/bin/python3.13 /usr/local/bin/python && \
    ln -sf /usr/bin/pip3.13 /usr/local/bin/pip3 && \
    ln -sf /usr/bin/pip3.13 /usr/local/bin/pip

# 在系统范围启用 Git LFS。
RUN git lfs install --system

# 创建非 root 用户，提升运行安全性。
RUN useradd -m -u 1000 -s /bin/bash node && \
    mkdir -p "${OPENCLAW_HOME}" && \
    chown -R node:node /home/node

# 启动脚本会自动应用你要求的 OpenClaw 默认配置与可选 Discord allowlist JSON，
# 若未传入自定义命令，则默认启动 `openclaw gateway`。
COPY docker/entrypoint.sh /usr/local/bin/openclaw-entrypoint.sh
RUN chmod +x /usr/local/bin/openclaw-entrypoint.sh

WORKDIR /workspace
USER node

# OpenClaw 官方 Docker 文档默认 gateway 端口为 18789。
EXPOSE 18789

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]
CMD []
