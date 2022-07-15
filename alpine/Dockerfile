# syntax=docker/dockerfile:1.4

ARG INADYN_TAG=v2.9.1
ARG INADYN_SHA256=7370eb7ad5d33a9cf2e7e4a6a86c09587fbf9592cd357c6f472c33f575bac26d
ARG LIBCONFUSE_TAG=v3.3
ARG LIBCONFUSE_SHA256=3a59ded20bc652eaa8e6261ab46f7e483bc13dad79263c15af42ecbb329707b8
ARG ALPINE_IMAGE=alpine:3.16


FROM ${ALPINE_IMAGE} AS fetch-archives

ARG INADYN_TAG
ARG INADYN_SHA256
ARG LIBCONFUSE_TAG
ARG LIBCONFUSE_SHA256

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked <<EOF
#!/bin/ash -eu
apk add --update-cache \
    ca-certificates \
    curl \
    #
EOF

RUN <<EOF
#!/bin/ash -eu
curl -Lo confuse.tar.gz "https://github.com/libconfuse/libconfuse/releases/download/${LIBCONFUSE_TAG}/confuse-${LIBCONFUSE_TAG#v}.tar.gz"
echo "${LIBCONFUSE_SHA256}  confuse.tar.gz" | sha256sum -cs
curl -Lo inadyn.tar.gz "https://github.com/troglobit/inadyn/releases/download/${INADYN_TAG}/inadyn-${INADYN_TAG#v}.tar.gz"
echo "${INADYN_SHA256}  inadyn.tar.gz" | sha256sum -cs
EOF


FROM ${ALPINE_IMAGE} AS build-confuse

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked <<EOF
#!/bin/ash -eu
apk add --update-cache \
    gcc \
    make \
    musl-dev \
    #
EOF

ENV CC=gcc
COPY --from=fetch-archives /confuse.tar.gz .

RUN <<EOF
#!/bin/ash -eu
mkdir ~/confuse ~/build
tar xf confuse.tar.gz --strip-components=1 -C ~/confuse
cd ~/build
~/confuse/configure --disable-examples --disable-nls --disable-rpath --prefix=${HOME}/install
make
make install
EOF


FROM ${ALPINE_IMAGE} AS build-inadyn

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked <<EOF
#!/bin/ash -eu
apk add --update-cache \
    gcc \
    libressl-dev \
    make \
    musl-dev \
    #
EOF

ENV CC=gcc
COPY --from=fetch-archives /inadyn.tar.gz .
COPY --from=build-confuse /root/install/include /usr/local/include
COPY --from=build-confuse /root/install/lib /usr/local/lib

RUN <<EOF
#!/bin/ash -eu
mkdir ~/inadyn ~/build
tar xf inadyn.tar.gz --strip-components=1 -C ~/inadyn
cd ~/build
~/inadyn/configure --enable-openssl --sysconfdir=/data --localstatedir=/var
make
make install
EOF


FROM ${ALPINE_IMAGE}

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked <<EOF
#!/bin/ash -eu
apk add --update-cache \
    ca-certificates \
    libressl-dev \
    #
EOF

COPY --from=build-confuse /root/install/lib /usr/local/lib
COPY --from=build-inadyn /usr/local/sbin/inadyn /usr/local/bin

ENTRYPOINT ["/usr/local/bin/inadyn"]
CMD ["--foreground"]
