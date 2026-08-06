# Reproduces the host FluidSynth's own Azure Pipelines Android job builds
# on (Microsoft-hosted `ubuntu-22.04` image), so build.sh's assumptions
# about available apt packages hold.
#
# Build:  docker build -t manul-relink-build .
# Run:    docker run --rm -v "$(pwd)/work:/work/work" -v "$(pwd)/out:/work/out" manul-relink-build
FROM ubuntu:22.04

# Packages the pipeline installs across its 'apt-get install wget tar' and
# 'apt-get install build-tools' steps, plus unzip/curl/git which the
# pipeline gets for free from the hosted image and this recipe needs
# explicitly, and sha256sum/sha1sum (coreutils, present by default) for
# checksum verification.
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-suggests --no-install-recommends \
      wget curl ca-certificates unzip tar bzip2 xz-utils \
      gettext zlib1g-dev autogen automake autoconf libtool pkg-config \
      autotools-dev build-essential meson ninja-build python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY versions.sh fetch-toolchain.sh build.sh ./

RUN ./fetch-toolchain.sh

ENTRYPOINT ["./build.sh"]
