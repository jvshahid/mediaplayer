# SDK=~/bin/adt-bundle-linux/sdk/
# NDK=~/bin/android-ndk-r8c

DEBUG=0
NOGOUM=0
android=$(SDK)/tools/android
facebook=deps/facebook/facebook
slidingmenu=deps/SlidingMenu/library
ffmpeg_parent=deps/ffmpeg
ffmpeg=$(ffmpeg_parent)/android
libs=libs/armeabi
class_dir=bin/classes
class=org/extremesolution/nilefm/media/AACPlayer.class
class_name=$(subst .class,,$(subst /,.,$(class)))
toolchain=/tmp/toolchain

all: package
.phony: setup sdk all install prepackage package properties resources

#
# Create the local.properites file in all this project and all its dependencies
#
sdk=$(if ${SDK},,$(error You must define SDK, please provide make with the location of the SDK, e.g. make SDK='path to the sdk'))
ndk=$(if ${NDK},,$(error You must define NDK, please provide make with the location of the NDK, e.g. make NDK='path to the ndk'))

setup: resources properties

resources:
ifeq ($(NOGOUM), 1)
	$(eval $@_appname := nogoumfm)
	$(eval $@_prefix  := ${PWD}/nogoumfm-specific)
else
	$(eval $@_appname := nilefm)
	$(eval $@_prefix  := ${PWD}/nilefm-specific)
endif
# change the name of the app in the build.xml file to appname
	$(android) update project -p $$(dirname $@) -n $($@_appname)
# replace the token {{appname}} with the name of the app in all xml/java files
	ant -Dappname=$($@_appname) replace

# create symlinks to the app specific resources in the res/ directory
	ln -f -s $($@_prefix)/res/values/strings-specific.xml res/values/strings-specific.xml
	ln -f -s $($@_prefix)/res/values/analytics.xml res/values/analytics.xml
	for resolution in hdpi mdpi ldpi; do \
		for name in about_us_menu_bar.png ic_launcher.png menu_bar_logo.png splash_background.png splash_logo.png channel_logo.png; do \
      ln -f -s $($@_prefix)/res/drawable-$$resolution/$$name res/drawable-$$resolution/$$name; \
    done; \
		ln -f -s $($@_prefix)/res/drawable-$$resolution/presenter_page_image_holder.png res/drawable-$$resolution/presenter_page_image_holder.png; \
  done
	ln -f -s $($@_prefix)/res/drawable-xhdpi/presenter_page_image_holder.png res/drawable-xhdpi/presenter_page_image_holder.png
	ln -f -s $($@_prefix)/res/drawable-xhdpi/ic_launcher.png res/drawable-xhdpi/ic_launcher.png
	ln -f -s $($@_prefix)/res/layout/header.xml res/layout/header.xml
	ln -f -s $($@_prefix)/res/layout/about_us_header.xml res/layout/about_us_header.xml
	ln -f -s $($@_prefix)/res/layout/menu_bar.xml res/layout/menu_bar.xml
	ln -f -s $($@_prefix)/res/layout/presenter_page_layout.xml res/layout/presenter_page_layout.xml
	ln -f -s $($@_prefix)/res/layout/show_page_layout.xml res/layout/show_page_layout.xml
	ln -f -s $($@_prefix)/res/layout/live_streaming_layout.xml res/layout/live_streaming_layout.xml
	ln -f -s $($@_prefix)/res/layout/schedule_row_layout.xml res/layout/schedule_row_layout.xml
	ln -f -s $($@_prefix)/res/layout/facebook_webview.xml res/layout/facebook_webview.xml
	ln -f -s $($@_prefix)/res/layout/youtube_row_layout.xml res/layout/youtube_row_layout.xml

$(facebook)/local.properties:
	${sdk}
	sed 's/ -Werror//g' $(facebook)/ant.properties > /tmp/facebook.ant.properties
	cp /tmp/facebook.ant.properties $(facebook)/ant.properties
	$(android) update project -p $$(dirname $@) -t 'android-15'

$(slidingmenu)/local.properties:
	${sdk}
	sed 's/android.library.reference.1=..\/ABS//' $(slidingmenu)/project.properties > /tmp/sliding.ant.properties
	cp /tmp/sliding.ant.properties $(slidingmenu)/project.properties
	$(android) update project -p $$(dirname $@) -t 'Google Inc.:Google APIs:15'

local.properties:
	${sdk}
	$(android) update project -p $$(dirname $@)

properties: $(facebook)/local.properties $(slidingmenu)/local.properties local.properties

#
# Create the android toolchain under /tmp/my-toolchain
#
uname_s := $(shell sh -c 'uname -s 2>/dev/null || echo not')
$(toolchain):
	${ndk}
ifeq ($(uname_s),Darwin)
	$(eval $@_toolchainsys := --system=darwin-x86_64)
else
	$(eval $@_toolchainsys := --system=linux-x86_64)
endif
	$(NDK)/build/tools/make-standalone-toolchain.sh $($@_toolchainsys) --platform=android-8 --install-dir=$@

#
# Create the ffmpeg.so library
#
export PATH := $(toolchain)/arm-linux-androideabi/bin:$(PATH)
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
    --no-whole-archive $(toolchain)/lib/gcc/arm-linux-androideabi/4.6/libgcc.a \
    -L$(toolchain)/sysroot/usr/lib -lc -lm -lz -ldl -llog

#
# Create the native part of our application
#
prepackage: setup
ifeq ($(DEBUG), 1)
	ant debug
else
	ant release
endif

$(libs)/libmedia-jni.so: prepackage $(ffmpeg)/lib/libffmpeg.so jni/media-decoder.c jni/media-decoder.h
	${ndk}
	javah -o jni/media-decoder.h -classpath $(class_dir) $(class_name)
ifeq ($(DEBUG), 1)
	$(NDK)/ndk-build NDK_DEBUG=1
else
	$(NDK)/ndk-build
endif

libs: setup $(libs)/libmedia-jni.so

package: libs
ifeq ($(DEBUG), 1)
	ant debug
else
	ant release
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
	ant clean
	ant -Dappname=$($@_appname) unreplace

distclean:
	git checkout .
	git clean -dfx
	for i in deps/*; do cd $$i; git checkout .; git clean -dfx; cd -; done
