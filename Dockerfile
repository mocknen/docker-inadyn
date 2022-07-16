# syntax=docker/dockerfile:1.4

ARG CONFUSE_TAG=v3.3
ARG CONFUSE_SHA256=3a59ded20bc652eaa8e6261ab46f7e483bc13dad79263c15af42ecbb329707b8
ARG INADYN_TAG=v2.9.1
ARG INADYN_SHA256=7370eb7ad5d33a9cf2e7e4a6a86c09587fbf9592cd357c6f472c33f575bac26d
ARG DEBIAN_IMAGE=debian:11-slim
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian11:nonroot


FROM ${DEBIAN_IMAGE} AS curl

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    ca-certificates \
    curl \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF


FROM curl AS fetch-confuse
ARG CONFUSE_TAG
ARG CONFUSE_SHA256

RUN <<EOF
#!/bin/bash -eu
curl -Lo confuse.tar.gz "https://github.com/libconfuse/libconfuse/releases/download/${CONFUSE_TAG}/confuse-${CONFUSE_TAG#v}.tar.gz"
echo "${CONFUSE_SHA256}  /confuse.tar.gz" | sha256sum -c --status
EOF


FROM curl AS fetch-inadyn
ARG INADYN_TAG
ARG INADYN_SHA256

RUN <<EOF
#!/bin/bash -eu
curl -Lo /inadyn.tar.gz "https://github.com/troglobit/inadyn/releases/download/${INADYN_TAG}/inadyn-${INADYN_TAG#v}.tar.gz"
echo "${INADYN_SHA256}  /inadyn.tar.gz" | sha256sum -c --status
EOF


FROM ${DEBIAN_IMAGE} AS build-confuse

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    clang \
    make \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

COPY --from=fetch-confuse /confuse.tar.gz .
ENV CC=clang

RUN <<EOF
#!/bin/bash -eu
tar xf confuse.tar.gz --strip-components=1 --one-top-level=confuse
mkdir confuse/build
cd confuse/build
../configure --disable-examples --disable-nls --disable-rpath
make
make install
EOF


FROM ${DEBIAN_IMAGE} AS build-inadyn

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    clang \
    make \
    libssl-dev \
    pkg-config \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

COPY --from=fetch-inadyn /inadyn.tar.gz .
COPY --from=build-confuse /usr/local/lib/libconfuse.a /usr/local/lib
COPY --from=build-confuse /usr/local/lib/pkgconfig /usr/local/lib/pkgconfig
COPY --from=build-confuse /usr/local/include /usr/local/include
ENV CC=clang

RUN <<EOF
#!/bin/bash -eu
tar xf inadyn.tar.gz --strip-components=1 --one-top-level=inadyn
mkdir inadyn/build
cd inadyn/build
../configure --sysconfdir=/data --enable-openssl
make
make install-strip
EOF


FROM ${DISTROLESS_IMAGE}

COPY --from=build-inadyn /usr/local/sbin/inadyn /inadyn
WORKDIR /home/nonroot/.cache/inadyn
ENTRYPOINT ["/inadyn"]
CMD ["--foreground", "--no-pidfile"]
