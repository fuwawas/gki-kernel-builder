# GKI 内核编译环境 —— 不用在本机装 Bazel / clang / 各种依赖
#
# 用法：
#   docker build -t gki-builder .
#   docker run --rm -it -v "$PWD/gki-out:/work/gki-out" gki-builder -v android14-6.1-138
#
# 或者更省事，直接用 docker-run.sh：
#   ./docker-run.sh -v android14-6.1-138
#
# 硬件要求：≥ 4 核 CPU、≥ 16GB 内存、≥ 40GB 可用磁盘。
# Docker Desktop 用户请先在设置里把内存调到 8GB 以上（默认 2GB 会编译失败）。

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libssl-dev bison flex libelf-dev dwarves \
        ccache python3 python3-pip git curl ca-certificates \
        clang lld llvm bc rsync cpio perl patch zip unzip gawk zstd tar \
        file bzip2 xz-utils rsync procps \
    && rm -rf /var/lib/apt/lists/*

# Bazelisk 是 Kleaf（Google 的内核构建系统）要求的 bazel 版本管理器，
# 缺了它 build_kernel.sh 会报 "bazel not found"。
# 按实际架构选二进制，Apple Silicon / ARM 服务器也能用。
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64|amd64) BAZEL_ARCH=amd64 ;; \
        aarch64|arm64) BAZEL_ARCH=arm64 ;; \
        *) echo "不支持的架构: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/bazel \
        "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${BAZEL_ARCH}" \
    && chmod +x /usr/local/bin/bazel

COPY gkibuild.sh /usr/local/bin/gkibuild.sh
RUN chmod +x /usr/local/bin/gkibuild.sh

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/gkibuild.sh"]
