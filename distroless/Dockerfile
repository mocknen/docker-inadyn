# syntax=docker/dockerfile:1.4

ARG INADYN_TAG=v2.9.1
ARG INADYN_SHA256=7370eb7ad5d33a9cf2e7e4a6a86c09587fbf9592cd357c6f472c33f575bac26d
ARG DEBIAN_IMAGE=debian:11-slim
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian11


FROM ${DEBIAN_IMAGE} AS fetch-package

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    ca-certificates \
    curl \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

ARG INADYN_TAG
ARG INADYN_SHA256

RUN <<EOF
#!/bin/bash -eu
curl -Lo ~/inadyn.tar.gz "https://github.com/troglobit/inadyn/releases/download/${INADYN_TAG}/inadyn-${INADYN_TAG#v}.tar.gz"
echo "${INADYN_SHA256}  ${HOME}/inadyn.tar.gz" | sha256sum -c --status
EOF


FROM ${DEBIAN_IMAGE} AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    ca-certificates \
    clang \
    libconfuse-dev \
    libssl-dev \
    make \
    pkg-config \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

ENV CC=clang
COPY --from=fetch-package /root/inadyn.tar.gz /root

RUN <<EOF
#!/bin/bash -eu
tar xf ~/inadyn.tar.gz --strip-components=1 -C ~ --one-top-level=inadyn
mkdir ~/build
cd ~/build
~/inadyn/configure --enable-openssl --sysconfdir=/data --localstatedir=/var
make
make install
EOF


FROM ${DISTROLESS_IMAGE}

COPY --from=builder \
    /usr/lib/x86_64-linux-gnu/libconfuse.so.2 \
    /usr/lib/x86_64-linux-gnu/libconfuse.so.2.1.0 \
    /usr/lib/x86_64-linux-gnu
COPY --from=builder /usr/local/sbin/inadyn /inadyn

ENTRYPOINT ["/inadyn"]
CMD ["--foreground"]
