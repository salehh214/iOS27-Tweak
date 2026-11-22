TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = Camera
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS27Camera

iOS27Camera_FILES = Tweak.x
iOS27Camera_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iOS27Camera_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreImage CoreVideo Vision Photos

include $(THEOS_MAKE_PATH)/tweak.mk
