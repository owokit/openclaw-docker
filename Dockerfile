FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# 容器级默认变量：
# - OPENCLAW_HOME：非 root 用户的 OpenClaw 运行配置目录。
# - OPENCLAW_PORT：gateway 监听端口，可通过 -e OPENCLAW_PORT=xxxx 在运行时覆盖。
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    OPENCLAW_HOME=/home/node/.openclaw \
    OPENCLAW_PORT=18789

ARG OPENCLAW_VERSION=latest
ARG TARGETOS
ARG TARGETARCH

# 使用 dnf 安装运行时与工具链（包管理优先）：
# - nodejs：openclaw CLI 依赖（优先安装新版本，失败则自动降级）。
# - python3/pip：Python 运行时与 boto3 依赖。
# - git/git-lfs：你要求的 CI/CD 与仓库操作工具。
RUN set -eux; \
    dnf install -y --setopt=install_weak_deps=False \
      python3 \
      python3-pip \
      git \
      git-lfs \
      ca-certificates \
      curl-minimal \
      coreutils \
      findutils \
      grep \
      gzip \
      tar \
      unzip \
      shadow-utils; \
    for pkg in nodejs24 nodejs22 nodejs20 nodejs; do \
      if dnf install -y --setopt=install_weak_deps=False "${pkg}" nodejs-npm || dnf install -y --setopt=install_weak_deps=False "${pkg}"; then \
        break; \
      fi; \
    done; \
    if ! command -v npm >/dev/null 2>&1; then \
      dnf install -y --setopt=install_weak_deps=False nodejs-npm || dnf install -y --setopt=install_weak_deps=False npm; \
    fi; \
    node --version; \
    npm --version; \
    python3 --version; \
    dnf clean all; \
    rm -rf /var/cache/dnf

# 安装 AWS CLI v2（官方安装包，避免不同 Amazon Linux repo 包名差异导致失败）
RUN set -eux; \
    case "${TARGETARCH:-$(uname -m)}" in \
      amd64|x86_64) AWS_ARCH="x86_64" ;; \
      arm64|aarch64) AWS_ARCH="aarch64" ;; \
      *) echo "Unsupported arch for awscli: ${TARGETARCH:-$(uname -m)}" >&2; exit 1 ;; \
    esac; \
    tmp="$(mktemp -d)"; \
    cd "${tmp}"; \
    curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"; \
    unzip -q awscliv2.zip; \
    ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update; \
    /usr/local/bin/aws --version; \
    cd /; \
    rm -rf "${tmp}"

# 安装 GitHub CLI（gh）
# 按 GitHub 官方 RPM 指南安装（兼容 Amazon Linux）。
RUN set -eux; \
    if dnf --version 2>/dev/null | head -n1 | grep -q '^dnf5'; then \
      dnf install -y --setopt=install_weak_deps=False dnf5-plugins; \
      dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo; \
    else \
      dnf install -y --setopt=install_weak_deps=False 'dnf-command(config-manager)'; \
      dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo; \
    fi; \
    dnf install -y --setopt=install_weak_deps=False gh --repo gh-cli; \
    gh --version; \
    dnf clean all; \
    rm -rf /var/cache/dnf

# 全局安装 OpenClaw CLI，并安装 AWS 自动化常用的 boto3。
RUN node --version && npm --version && \
    npm install -g --omit=dev --no-audit "openclaw@${OPENCLAW_VERSION}" && \
    npm cache clean --force && \
    python3 -m pip install --no-cache-dir --upgrade pip boto3

# 统一 python/pip 命令名，避免版本差异导致命令不一致。
RUN ln -sf /usr/bin/python3 /usr/local/bin/python3 && \
    ln -sf /usr/bin/python3 /usr/local/bin/python && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip3 && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip

# 在系统范围启用 Git LFS。
RUN git lfs install --system

# 创建非 root 用户，提升运行安全性。
RUN useradd -m -u 1000 -s /sbin/nologin node && \
    mkdir -p "${OPENCLAW_HOME}" && \
    chown -R node:node /home/node && \
    chmod 700 "${OPENCLAW_HOME}"

# 启动脚本会自动应用你要求的 OpenClaw 默认配置与可选 Discord allowlist JSON，
# 若未传入自定义命令，则默认启动 `openclaw gateway`。
COPY docker/entrypoint.sh /usr/local/bin/openclaw-entrypoint.sh
RUN chmod +x /usr/local/bin/openclaw-entrypoint.sh

WORKDIR /workspace
USER node

# OpenClaw 官方 Docker 文档默认 gateway 端口为 18789。
EXPOSE 18789

# 基础健康检查：检查本地 gateway 端口是否可连通。
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python3 -c "import os,socket; s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1', int(os.getenv('OPENCLAW_PORT','18789')))); s.close()" || exit 1

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]
CMD []
