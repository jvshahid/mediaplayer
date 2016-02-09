LOCAL_PATH := $(call my-dir)

#declare the prebuilt library
include $(CLEAR_VARS)
LOCAL_MODULE := ffmpeg-prebuilt
LOCAL_SRC_FILES := ../deps/ffmpeg/android/lib/libffmpeg.so
LOCAL_EXPORT_LDLIBS := ../deps/ffmpeg/android/lib/libffmpeg.so
LOCAL_PRELINK_MODULE := true
include $(PREBUILT_SHARED_LIBRARY)

#the media-jni library
include $(CLEAR_VARS)
LOCAL_MODULE := media-jni
LOCAL_SRC_FILES   := media-decoder.c
LOCAL_C_INCLUDES  := deps/ffmpeg/android/include
LOCAL_SHARED_LIBRARY := ffmpeg-prebuilt
LOCAL_LDLIBS      := -llog -lz -lm -lffmpeg
LOCAL_LDFLAGS     += -Ldeps/ffmpeg/android/lib
LOCAL_ALLOW_UNDEFINED_SYMBOLS=false
include $(BUILD_SHARED_LIBRARY)
