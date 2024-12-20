FROM docker.io/alpine:3.19 AS builder

RUN apk add --no-cache coreutils sequoia-sq tar wget zstd

WORKDIR /tmp

RUN wget http://mirror.cmt.de/archlinux/iso/latest/b2sums.txt
RUN wget http://mirror.cmt.de/archlinux/iso/latest/sha256sums.txt
RUN wget http://mirror.cmt.de/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst
RUN wget http://mirror.cmt.de/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst.sig
RUN sq --force wkd get pierre@archlinux.org -o release-key.pgp

# This might be pedantic given that the signature matches, but why not.
RUN b2sum --ignore-missing -c b2sums.txt
RUN sha256sum --ignore-missing -c sha256sums.txt
RUN sq verify --signer-file release-key.pgp --detached archlinux-bootstrap-x86_64.tar.zst.sig archlinux-bootstrap-x86_64.tar.zst

WORKDIR /

RUN mkdir /rootfs
RUN tar xf /tmp/archlinux-bootstrap-x86_64.tar.zst --numeric-owner -C /rootfs

FROM scratch
COPY --from=builder /rootfs/root.x86_64 /

# The bootstrap image is very minimal and we still have to setup pacman.
RUN pacman-key --init
RUN pacman-key --populate
RUN echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist

# This allows us to use this image for committing as well.
RUN pacman --noconfirm -Syu grub ostree rsync

# This allows using this container to make a deployment.
RUN ln -s sysroot/ostree /ostree

# This allows using pacstrap -N in a rootless container.
RUN echo 'root:1000:5000' > /etc/subuid
RUN echo 'root:1000:5000' > /etc/subgid

# Setup for building AUR packages
RUN pacman --noconfirm -Syu base-devel git sudo
RUN useradd -m builder
RUN echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/builder
RUN sed -i "s/debug lto/!debug lto/g" /etc/makepkg.conf
USER builder
RUN mkdir /home/builder/aur/
USER root
RUN mkdir /aur
COPY build-aur.sh /usr/bin/build-aur
