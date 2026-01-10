FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y \
      build-essential \
      gcc-aarch64-linux-gnu \
      g++-aarch64-linux-gnu \
      ccache \
      bison \
      flex \
      libssl-dev \
      libelf-dev \
      bc \
      kmod \
      cpio \
      u-boot-tools \
      device-tree-compiler \
      lz4 \
      git \
      wget \
      curl \
      vim \
    && rm -rf /var/lib/apt/lists/*

ENV CCACHE_DIR=/tmp/ccache
RUN mkdir -p /tmp/ccache && chmod 777 /tmp/ccache

ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-

WORKDIR /workspace
