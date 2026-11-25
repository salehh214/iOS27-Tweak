TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences Camera
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS27

iOS27_FILES = HomeScreen.x LockScreen.x ControlCenter.x WallpaperEditor.x HomeScreenEditor.x Gestures.x
iOS27_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iOS27_FRAMEWORKS = UIKit QuartzCore CoreGraphics ImageIO AVFoundation

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += iOS27Prefs iOS27Camera iOS27PadMode
include $(THEOS_MAKE_PATH)/aggregate.mk
