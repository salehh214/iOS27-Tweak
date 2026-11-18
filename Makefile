TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS27

iOS27_FILES = HomeScreen.x LockScreen.x ControlCenter.x
iOS27_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iOS27_FRAMEWORKS = UIKit QuartzCore CoreGraphics

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += iOS27Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
