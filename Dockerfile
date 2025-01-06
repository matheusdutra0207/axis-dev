#-- Build configuration --#
# ARCH_CFLAGS is supplied as a compile option
ARG ARCH_CFLAGS="-O2 -mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a9 -fomit-frame-pointer"
# AXIS_ARCH is the AXIS platform descriptor
ARG AXIS_ARCH=armv7hf
# BUILD_ROOT defines where in the build containers the building takes place
ARG BUILD_ROOT=/build-root
# DOCKERHUB_ARCH is the DockerHub platform descriptor
ARG DOCKERHUB_ARCH=arm32v7
# OPENCV_MODULES defines what OpenCV modules to build
ARG OPENCV_MODULES=core,imgproc,imgcodecs,videoio,objdetect,python3,video
# SDK_ROOT_DIR defines the root directory of the final SDK images
ARG SDK_ROOT_DIR=/axis/
# UBUNTU_ARCH is the Ubuntu platform descriptor
ARG UBUNTU_ARCH=armhf
# TARGET_TOOLCHAIN is the name of the compilation toolchain for the target platform
ARG TARGET_TOOLCHAIN=arm-linux-gnueabihf
# TARGET_ROOT defines where in the build containers the resulting application is put
ARG TARGET_ROOT=/target-root
# UBUNTU_VERSION defines the ubuntu version of the build and SDK containers
ARG UBUNTU_VERSION=20.04
# UBUNTU_CODENAME should be the ubuntu codename of the UBUNTU_VERSION used, e.g., focal, hirsute, ..
ARG UBUNTU_CODENAME=focal

#-- Versions of installed packages defined as repository tags --#
ARG NUMPY_VERSION=v1.17.3
ARG OPENBLAS_VERSION=v0.3.14
ARG OPENCV_VERSION=4.5.1
ARG PYTHON_VERSION=3.8.8
ARG PYTESSERACT_VERSION=0.3.7
ARG SCIPY_VERSION=v1.7.1
ARG TESSERACT_VERSION=4.1.1
ARG TFSERVING_VERSION=2.0.0

#-- Build parallelization  --#
ARG OPENBLAS_BUILD_CORES=2
ARG OPENCV_BUILD_CORES=2
ARG PYTHON_BUILD_CORES=4
ARG NUMPY_BUILD_CORES=4
ARG SCIPY_BUILD_CORES=4

#-- ACAP SDK configuration --#
ARG REPO=axisecp
ARG ACAP_SDK_IMAGE=acap-native-sdk
ARG ACAP_SDK_VERSION=1.1
ARG ACAP_SDK_TAG=${ACAP_SDK_VERSION}-${AXIS_ARCH}-ubuntu20.04


# Create a base image with build tools, env vars, etc.,
FROM ubuntu:${UBUNTU_VERSION} AS build-base

# Setup environment variables
ENV DEBIAN_FRONTEND=noninteractive
ARG BUILD_ROOT
ARG PYTHON_VERSION
ARG TARGET_TOOLCHAIN
ARG TARGET_ROOT
ARG UBUNTU_ARCH
ARG UBUNTU_CODENAME
ARG http_proxy
ARG https_proxy

# To support DOCKER_BUILDKIT=0, base ARGs are converted to ENVs to allow propagation
ENV BUILD_ROOT=$BUILD_ROOT
ENV TARGET_TOOLCHAIN=$TARGET_TOOLCHAIN
ENV TARGET_ROOT=$TARGET_ROOT
ENV UBUNTU_ARCH=$UBUNTU_ARCH
ENV UBUNTU_CODENAME=$UBUNTU_CODENAME
ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy


# Add source for target arch
RUN echo \
"deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ $UBUNTU_CODENAME main restricted universe multiverse\n\
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ $UBUNTU_CODENAME-updates main restricted universe multiverse\n\
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ $UBUNTU_CODENAME-backports main restricted universe multiverse\n\
deb [arch=amd64] http://security.ubuntu.com/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_CODENAME main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_CODENAME-updates main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_CODENAME-backports main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_CODENAME-security main restricted universe multiverse"\
 > /etc/apt/sources.list

# Get crosscompilation toolchain and related packages
RUN dpkg --add-architecture $UBUNTU_ARCH
RUN apt-get update && apt-get install -yf --no-install-recommends \
        autoconf \
        automake \
        autotools-dev \
        build-essential \
        ca-certificates \
        crossbuild-essential-$UBUNTU_ARCH \
        cmake \
        curl \
        gfortran-$TARGET_TOOLCHAIN \
        git \
        gfortran \
        libtool \
        pkg-config \
        python3-dev \
        python3-pip \
        python3-venv \
        wget \
 && update-ca-certificates \
 && apt-get clean

RUN mkdir -p ${TARGET_ROOT}
RUN mkdir -p ${BUILD_ROOT}

# Save a string of what python major.minor version we're using
# for paths, etc.
RUN echo python${PYTHON_VERSION} | sed 's/\([0-9]\.[0-9]*\)\.\([0-9]*\)/\1/' > /tmp/python_version


# Create a emulated base image with build tools, env vars, etc.,
FROM $DOCKERHUB_ARCH/ubuntu:${UBUNTU_VERSION} as build-base-arm
ARG BUILD_ROOT
ENV DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION
ARG TARGET_TOOLCHAIN
ARG TARGET_ROOT
ARG UBUNTU_ARCH
ARG http_proxy
ARG https_proxy

# To support DOCKER_BUILDKIT=0, base ARGs are converted to ENVs to allow propagation
ENV BUILD_ROOT=$BUILD_ROOT
ENV TARGET_TOOLCHAIN=$TARGET_TOOLCHAIN
ENV TARGET_ROOT=$TARGET_ROOT
ENV UBUNTU_ARCH=$UBUNTU_ARCH
ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy

# qemu is used to emulate arm
COPY --from=multiarch/qemu-user-static:x86_64-arm-5.2.0-2 /usr/bin/qemu-arm-static /usr/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gfortran \
        git \
        pkg-config \
    && update-ca-certificates

RUN mkdir -p ${TARGET_ROOT}
RUN mkdir -p ${BUILD_ROOT}

# Save a string of what python major.minor version we're using
# for paths, etc.
RUN echo python${PYTHON_VERSION} | sed 's/\([0-9]\.[0-9]*\)\.\([0-9]*\)/\1/' > /tmp/python_version


# Crosscompile OpenBLAS
FROM build-base AS build-openblas
ARG ARCH_CFLAGS
ARG OPENBLAS_BUILD_CORES
ARG OPENBLAS_VERSION
WORKDIR ${BUILD_ROOT}
RUN git clone --depth 1 --branch ${OPENBLAS_VERSION}  https://github.com/xianyi/OpenBLAS.git
WORKDIR ${BUILD_ROOT}/OpenBLAS
RUN HAVE_NEON=1 make -j ${OPENBLAS_BUILD_CORES} TARGET=CORTEXA9 CC=$TARGET_TOOLCHAIN-gcc FC=$TARGET_TOOLCHAIN-gfortran HOSTCC=gcc
RUN make install PREFIX=$TARGET_ROOT/usr


# Crosscompile Python
FROM build-base as build-python-cross
ARG ARCH_CFLAGS
ARG PYTHON_VERSION
ARG PYTHON_BUILD_CORES
RUN mkdir -p $BUILD_ROOT/python_deps
WORKDIR /usr/bin
RUN ln -s python3.*[0-9] python

# Get optional Python module dependencies
RUN apt-get install --reinstall --download-only -o=dir::cache=$BUILD_ROOT/python_deps -y -f \
        libbz2-dev:$UBUNTU_ARCH zlib1g-dev:$UBUNTU_ARCH libssl1.1:$UBUNTU_ARCH libffi-dev:$UBUNTU_ARCH libssl-dev:$UBUNTU_ARCH libreadline6-dev:$UBUNTU_ARCH
WORKDIR $TARGET_ROOT
RUN for f in $BUILD_ROOT/python_deps/archives/*.deb; do dpkg -x $f $TARGET_ROOT; done
RUN mv $TARGET_ROOT/lib/$TARGET_TOOLCHAIN/* $TARGET_ROOT/usr/lib/$TARGET_TOOLCHAIN/ && \
    rm -rf $TARGET_ROOT/lib

# Copy selected libs we need for python compilation
WORKDIR $TARGET_ROOT/usr/lib/$TARGET_TOOLCHAIN/
RUN cp -R libffi* libreadline* libssl* libz* libcrypt* libncurses* libunistring* libidn* libtinfo* libgpm* libbz2* ..
RUN cp -r $TARGET_ROOT/usr/include/$TARGET_TOOLCHAIN/* $TARGET_ROOT/usr/include/ && rm -r $TARGET_ROOT/usr/include/$TARGET_TOOLCHAIN

# Download Python
RUN curl https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz -o $BUILD_ROOT/python.tgz
RUN tar -xf $BUILD_ROOT/python.tgz -C $BUILD_ROOT/
WORKDIR $BUILD_ROOT/Python-$PYTHON_VERSION

# Setup crosscompilation environment
ENV CC=$TARGET_TOOLCHAIN-gcc
ENV CXX=$TARGET_TOOLCHAIN-g++
ENV AR=$TARGET_TOOLCHAIN-ar
ENV LD=$TARGET_TOOLCHAIN-ld
ENV RANLIB=$TARGET_TOOLCHAIN-ranlib
ENV CFLAGS="$ARCH_CFLAGS -I$TARGET_ROOT/usr/include"
ENV CXXFLAGS="$ARCH_CFLAGS -I$TARGET_ROOT/usr/include"
ENV CPPFLAGS="$ARCH_CFLAGS -I$TARGET_ROOT/usr/include"
ENV LDFLAGS="-L/usr/lib/$TARGET_TOOLCHAIN -L$TARGET_ROOT/usr/lib"
RUN ./configure --host=$TARGET_TOOLCHAIN --with-openssl=$TARGET_ROOT/usr \
    --build=x86_64-linux-gnu --prefix=$TARGET_ROOT/usr \
    --enable-shared --disable-ipv6 \
    ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no \
    --with-lto --enable-optimizations
RUN make HOSTPYTHON=/usr/bin/python3 -j $PYTHON_BUILD_CORES CROSS_COMPILE=$TARGET_TOOLCHAIN CROSS_COMPILE_TARGET=yes
RUN make altinstall HOSTPYTHON=python3 CROSS_COMPILE=$TARGET_TOOLCHAIN CROSS_COMPILE_TARGET=yes prefix=$TARGET_ROOT/usr
WORKDIR $TARGET_ROOT/usr/bin
RUN ln -s python3.*[0-9] python3
RUN mkdir -p $TARGET_ROOT/usr/include/$TARGET_TOOLCHAIN/$(cat /tmp/python_version) && \
    cp -r $TARGET_ROOT/usr/include/$(cat /tmp/python_version)/* $TARGET_ROOT/usr/include/$TARGET_TOOLCHAIN/$(cat /tmp/python_version)


# Continue Python install with installing
# pip in emulated environment
FROM build-base-arm as build-python
ENV PATH=$TARGET_ROOT/usr/bin:$PATH
ENV LD_LIBRARY_PATH=$TARGET_ROOT/usr/lib:$LD_LIBRARY_PATH
COPY --from=build-python-cross $TARGET_ROOT $TARGET_ROOT
WORKDIR ${BUILD_ROOT}/pip
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
RUN $TARGET_ROOT/usr/bin/python3 get-pip.py
# Fix to not use static paths to $TARGET_ROOT
RUN sed -i '1s/.*/#!\/usr\/bin\/env python3/g' $TARGET_ROOT/usr/bin/pip*


# Build NumPy with OpenBLAS
# This build is done emulated right now until more work
# has been put in researching how to crosscompile
# python packages
# Building numpy like this vs apt-get shows ~5% lower proc times
# in basic math ops
# Building numpy with OpenBLAS as BLAS/Lapack vs built-in BLAS/Lapack
# shows between 50% to 99% lower proc times depending on the linalg op used
FROM build-base-arm AS build-python-numpy
ARG ARCH_CFLAGS
ARG NUMPY_BUILD_CORES
ARG NUMPY_VERSION
ENV CFLAGS="$ARCH_CFLAGS"
ENV LD_LIBRARY_PATH=$BUILD_ROOT/usr/lib:$LD_LIBRARY_PATH
ENV NPY_NUM_BUILD_JOBS=$NUMPY_BUILD_CORES
ENV PATH=$BUILD_ROOT/usr/bin:$BUILD_ROOT/usr/local/bin:$PATH
COPY --from=build-openblas $TARGET_ROOT $BUILD_ROOT
COPY --from=build-python $TARGET_ROOT $BUILD_ROOT
WORKDIR $BUILD_ROOT
RUN git clone --depth 1 --branch ${NUMPY_VERSION}  https://github.com/numpy/numpy
WORKDIR $BUILD_ROOT/numpy
RUN cp site.cfg.example site.cfg
RUN echo "[openblas]\n" \
         "libraries = openblas\n" \
         "library_dirs = ${BUILD_ROOT}/usr/lib\n" \
         "include_dirs = ${BUILD_ROOT}/usr/include\n" \
         "[default]\n" \
         "include_dirs = ${BUILD_ROOT}/usr/include\n" \
         "library_dirs = ${BUILD_ROOT}/usr/lib\n" \
         "[lapack]\n" \
         "lapack_libs = openblas\n" \
         "library_dirs = ${BUILD_ROOT}/usr/lib\n" \
         >> site.cfg
RUN CC="gcc -I$BUILD_ROOT/usr/include -I$BUILD_ROOT/usr/include/$(cat /tmp/python_version) $ARCH_CFLAGS" python3 -m pip install cython
RUN pip install setuptools==63.4.2
RUN python3 -m pip install --upgrade cython==0.29.37
RUN CC="gcc -I$BUILD_ROOT/usr/include -I$BUILD_ROOT/usr/include/$(cat /tmp/python_version) $ARCH_CFLAGS" python3 setup.py config
RUN rm -r branding/
RUN CC="gcc -I$BUILD_ROOT/usr/include -I$BUILD_ROOT/usr/include/$(cat /tmp/python_version) $ARCH_CFLAGS" python3 -m pip install . -v --prefix=$TARGET_ROOT/usr --no-build-isolation
RUN mkdir -p ${BUILD_ROOT}/python-numpy-deps
RUN apt-get install --reinstall --download-only -o=dir::cache=${BUILD_ROOT}/python-numpy-deps -y --no-install-recommends \
        libgfortran5
RUN for f in ${BUILD_ROOT}/python-numpy-deps/archives/*.deb; do dpkg -x $f $TARGET_ROOT; done



FROM axisecp/acap-computer-vision-sdk:1.1-armv7hf AS cv-sdk

FROM arm32v7/ubuntu:20.04

# Add the CV packages
# Add the CV packages
COPY --from=cv-sdk /axis/opencv /
COPY --from=build-python /target-root /
COPY --from=build-python-numpy /target-root /
COPY --from=cv-sdk /axis/openblas /

# Add your application files
COPY app /app
WORKDIR /app
CMD ["python3", "teste.py"]