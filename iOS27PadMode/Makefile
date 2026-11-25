TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS27PadMode

iOS27PadMode_FILES = Tweak.x
iOS27PadMode_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iOS27PadMode_FRAMEWORKS = UIKit QuartzCore

include $(THEOS)/makefiles/tweak.mk
