# SDK=~/bin/adt-bundle-linux/sdk/
# NDK=~/bin/android-ndk-r8c

DEBUG=0
android=$(SDK)/tools/android
ffmpeg_parent=deps/ffmpeg
ffmpeg=$(ffmpeg_parent)/android
libs=libs/armeabi
ifeq ($(DEBUG),1)
class_dir=mediaplayer/build/intermediates/classes/debug
else
class_dir=mediaplayer/build/intermediates/classes/release
endif
class=com/github/jvshahid/mediaplayer/AACPlayer.class
class_name=$(subst .class,,$(subst /,.,$(class)))
toolchain=/tmp/toolchain

all: package
.phony: sdk all prepackage package

#
# Create the local.properites file in all this project and all its dependencies
#
sdk=$(if ${SDK},,$(error You must define SDK, please provide make with the location of the SDK, e.g. make SDK='path to the sdk'))
ndk=$(if ${NDK},,$(error You must define NDK, please provide make with the location of the NDK, e.g. make NDK='path to the ndk'))

#
# Create the android toolchain under /tmp/my-toolchain
#
uname_s := $(shell sh -c 'uname -s 2>/dev/null || echo not')
toolchain_ver := 4.9
$(toolchain):
	${ndk}
ifeq ($(uname_s),Darwin)
	$(eval $@_toolchainsys := --system=darwin-x86_64)
else
	$(eval $@_toolchainsys := --system=linux-x86_64)
endif
	bash $(NDK)/build/tools/make-standalone-toolchain.sh $($@_toolchainsys) --toolchain=arm-linux-androideabi-$(toolchain_ver) --platform=android-8 --install-dir=$@

#
# Create the ffmpeg.so library
#
export PATH := $(toolchain)/arm-linux-androideabi/bin:$(PATH)
export ANDROID_HOME := $(SDK)
$(ffmpeg_parent)/config.h: $(toolchain)
	CALLED_FROM_MAKE=1 DEBUG=$(DEBUG) ./build.sh

$(ffmpeg)/lib/libffmpeg.so: $(ffmpeg_parent)/config.h
	$(MAKE) -C $(ffmpeg_parent) install
	$(toolchain)/arm-linux-androideabi/bin/ar d $(ffmpeg)/lib/libavcodec.a log2_tab.o
	$(toolchain)/arm-linux-androideabi/bin/ar d $(ffmpeg)/lib/libavformat.a log2_tab.o
	$(toolchain)/arm-linux-androideabi/bin/ar d $(ffmpeg)/lib/libswresample.a log2_tab.o

# group all the libraries in one so file
	$(toolchain)/arm-linux-androideabi/bin/ld -soname libffmpeg.so -shared -nostdlib -Bsymbolic \
    --no-undefined -o $(ffmpeg)/lib/libffmpeg.so \
    --whole-archive \
               $(ffmpeg)/lib/libavcodec.a \
               $(ffmpeg)/lib/libavformat.a \
               $(ffmpeg)/lib/libswresample.a \
               $(ffmpeg)/lib/libswscale.a \
               $(ffmpeg)/lib/libavfilter.a \
               $(ffmpeg)/lib/libavutil.a \
    --no-whole-archive $(toolchain)/lib/gcc/arm-linux-androideabi/$(toolchain_ver)/libgcc.a \
    -L$(toolchain)/sysroot/usr/lib -lc -lm -lz -ldl -llog

#
# Create the native part of our application
#
prepackage:
ifeq ($(DEBUG), 1)
	./gradlew compileDebugSources
else
	./gradlew compileReleaseSources
endif

$(libs)/libmedia-jni.so: prepackage \
				$(ffmpeg)/lib/libffmpeg.so \
				jni/media-decoder.c \
				jni/media-decoder.h
	${ndk}
	javah -o jni/media-decoder.h -classpath $(class_dir) $(class_name)
ifeq ($(DEBUG), 1)
	$(NDK)/ndk-build NDK_DEBUG=1
else
	$(NDK)/ndk-build
endif

mediaplayer/src/main/jniLibs/armeabi:
	mkdir -p mediaplayer/src/main/jniLibs/armeabi

mediaplayer/src/main/jniLibs/armeabi/libmedia-jni.so: \
				$(libs)/libmedia-jni.so \
				mediaplayer/src/main/jniLibs/armeabi
	cp $< $@

mediaplayer/src/main/jniLibs/armeabi/libffmpeg.so: \
				$(ffmpeg)/lib/libffmpeg.so \
				mediaplayer/src/main/jniLibs/armeabi
	cp $< $@

libs: mediaplayer/src/main/jniLibs/armeabi/libffmpeg.so \
				mediaplayer/src/main/jniLibs/armeabi/libmedia-jni.so

package: libs
ifeq ($(DEBUG), 1)
	./gradlew assembleDebug
else
	./gradlew assembleRelease
endif

install: libs
ifeq ($(DEBUG), 1)
	ant debug install
else
	ant release install
endif

start: libs
	${sdk}
ifeq ($(NOGOUM), 1)
	$(SDK)/platform-tools/adb shell am start -n org.extremesolution.nogoumfm/org.extremesolution.nilefm.NileFM
else
	$(SDK)/platform-tools/adb shell am start -n org.extremesolution.nilefm/org.extremesolution.nilefm.NileFM
endif

clean:
	./gradlew clean

distclean: clean
	git checkout .
	git clean -dfx
	for i in deps/*; do cd $$i; git checkout .; git clean -dfx; cd -; done
