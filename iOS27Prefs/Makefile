TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = iOS27Prefs

iOS27Prefs_FILES = IOS27RootListController.m
iOS27Prefs_FRAMEWORKS = UIKit
iOS27Prefs_PRIVATE_FRAMEWORKS = Preferences
iOS27Prefs_INSTALL_PATH = /Library/PreferenceBundles
iOS27Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/iOS27Prefs.plist$(ECHO_END)
