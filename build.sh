#!/usr/bin/env bash

#         --extra-cflags='-fpic -DANDROID -DHAVE_SYS_UIO_H=1 -Dipv6mr_interface=ipv6mr_ifindex -fasm -Wno-psabi -fno-short-enums -fno-strict-aliasing -mfloat-abi=softfp -mfpu=vfpv3-d16 -marm -march=armv7-a' \

# This script will build the native part of the applilcation

if [ -z "$CALLED_FROM_MAKE" ]; then
    echo "Please don't call this script directly, instead use make"
    exit 1
fi

ffmpeg=deps/ffmpeg

cd $ffmpeg

export PATH

prefix=$PWD/android/
toolchain=/tmp/toolchain

if [ $DEBUG -ne 1 ]; then
    debug_opt="--disable-debug --disable-stripping"
fi

# Fix to use soft floating point

cat <<EOF > libavutil/arm/float_dsp_init_vfp.c
#include "libavutil/float_dsp.h"
#include "cpu.h"
#include "float_dsp_arm.h"

void ff_vector_fmul_vfp(float *dst, const float *src0, const float *src1,
                        int len);

void ff_float_dsp_init_vfp(AVFloatDSPContext *fdsp)
{
   return;
}
EOF

# Notes about the configure options:
#   1. disable-neon: without this flag we'll hit SIGBUS in the neon assembly
./configure \
    --disable-yasm \
    --prefix=$prefix \
    --enable-cross-compile \
    --arch=arm \
    --disable-neon \
    --cc=$toolchain/bin/arm-linux-androideabi-gcc \
    --target-os=linux \
    --disable-doc \
    --disable-ffplay \
    --disable-ffmpeg \
    --disable-ffprobe \
    --disable-ffserver \
    --disable-avdevice \
    --disable-postproc \
    $debug_opt && \
    sed 's/HAVE_SYMVER 1/HAVE_SYMVER 0/g' config.h > /tmp/ffmpeg.config.h && \
    cp /tmp/ffmpeg.config.h config.h
