# syntax=docker/dockerfile:1.4

ARG OPENSSL_TAG=openssl-3.0.5
ARG OPENSSL_SHA256=b6363cf1bca88f0a46a768883a225e644135432d6a51ab1c4660ab58af541078
ARG CONFUSE_TAG=v3.3
ARG CONFUSE_SHA256=3a59ded20bc652eaa8e6261ab46f7e483bc13dad79263c15af42ecbb329707b8
ARG INADYN_TAG=v2.9.1
ARG INADYN_SHA256=7370eb7ad5d33a9cf2e7e4a6a86c09587fbf9592cd357c6f472c33f575bac26d
ARG DEBIAN_IMAGE=debian:11-slim
ARG DISTROLESS_IMAGE=gcr.io/distroless/static-debian11:nonroot
ARG CC_DEFAULT=clang
ARG MAKEFLAGS_DEFAULT


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


FROM curl AS fetch-openssl
ARG OPENSSL_TAG
ARG OPENSSL_SHA256

RUN <<EOF
#!/bin/bash -eu
curl -Lo openssl.tar.gz "https://github.com/openssl/openssl/archive/${OPENSSL_TAG}.tar.gz"
echo "${OPENSSL_SHA256}  /openssl.tar.gz" | sha256sum -c --status
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


FROM ${DEBIAN_IMAGE} AS fetch-essentials

WORKDIR /tmp

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    binutils \
    xz-utils \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
mkdir /essentials
readonly libc6_deb="$(apt download libc6 --print-uris | cut -f2 -d' ')"
apt download libc6
ar x "${libc6_deb}"
tar xf data.tar.xz -C /essentials
rm control.tar.xz data.tar.xz debian-binary "${libc6_deb}"
if [ "$(uname -m)" == "armv7l" ]; then
    readonly libatomic1_deb="$(apt download libatomic1 --print-uris | cut -f2 -d' ')"
    apt download libatomic1
    ar x "${libatomic1_deb}"
    tar xf data.tar.xz -C /essentials
    rm control.tar.xz data.tar.xz debian-binary "${libatomic1_deb}"
fi
rm -r /essentials/usr/share
EOF


FROM ${DEBIAN_IMAGE} AS fetch-libgcc-10-dev

WORKDIR /tmp

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    binutils \
    xz-utils \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
readonly archive="$(apt download libc6 --print-uris | cut -f2 -d' ')"
apt download libc6
ar x "${archive}"
mkdir /libc6
tar xf data.tar.xz -C /libc6
rm -r /libc6/usr/share
EOF


FROM ${DEBIAN_IMAGE} AS build-base

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    clang \
    make \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

ARG CC_DEFAULT
ARG MAKEFLAGS_DEFAULT
ENV CC=${CC_DEFAULT}
ENV MAKEFLAGS=${MAKEFLAGS_DEFAULT}


FROM build-base AS build-openssl

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    perl \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

COPY --from=fetch-openssl /openssl.tar.gz .

RUN <<EOF
#!/bin/bash -eu
tar xf openssl.tar.gz --strip-components=1 --one-top-level=openssl
mkdir openssl/build
cd openssl/build
../Configure no-shared
make install_sw
EOF


FROM build-base AS build-confuse

COPY --from=fetch-confuse /confuse.tar.gz .

RUN <<EOF
#!/bin/bash -eu
tar xf confuse.tar.gz --strip-components=1 --one-top-level=confuse
mkdir confuse/build
cd confuse/build
../configure --disable-examples --disable-nls --disable-rpath
make install
rm /usr/local/lib/libconfuse.{la,so{,.2{,.1.0}}}
EOF


FROM build-base AS build-inadyn

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked <<EOF
#!/bin/bash -eu
apt update
readonly packages=( \
    pkg-config \
)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ${packages[@]}
EOF

COPY --from=fetch-inadyn /inadyn.tar.gz .
COPY --from=build-confuse /usr/local \
                          /usr/local
COPY --from=build-openssl /usr/local \
                          /usr/local

ENV PKG_CONFIG='pkg-config --static'
ENV PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig

RUN <<EOF
#!/bin/bash -eu
tar xf inadyn.tar.gz --strip-components=1 --one-top-level=inadyn
mkdir inadyn/build
cd inadyn/build
../configure --sysconfdir=/data --enable-openssl
make install-strip
EOF


FROM ${DISTROLESS_IMAGE}

COPY --from=fetch-essentials /essentials /
COPY --from=build-inadyn /usr/local/sbin/inadyn /usr/local/sbin/inadyn

WORKDIR /home/nonroot/.cache/inadyn

ENTRYPOINT ["/usr/local/sbin/inadyn"]
CMD ["--foreground", "--no-pidfile"]
