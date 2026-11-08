# Build independently against the target distribution's Qt and libc.
ARG DISTRO=ubuntu:24.04
FROM ${DISTRO}
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build python3 curl ca-certificates pkg-config zlib1g-dev \
    qt6-base-dev qt6-declarative-dev qt6-multimedia-dev qt6-svg-dev qt6-wayland \
    qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript \
    qml6-module-qttest xvfb xauth file dpkg-dev desktop-file-utils \
    && if apt-cache show qt6-svg-plugins >/dev/null 2>&1; then apt-get install -y --no-install-recommends qt6-svg-plugins; fi \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/install-rust.sh \
    && sh /tmp/install-rust.sh -y --profile minimal && rm /tmp/install-rust.sh
ENV PATH="/root/.cargo/bin:${PATH}"
WORKDIR /work
