ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlitchFrameCC

GlitchFrameCC_BUNDLE_EXTENSION = bundle
GlitchFrameCC_FILES = GlitchFrameCC.m
GlitchFrameCC_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
GlitchFrameCC_FRAMEWORKS = UIKit
# CCUIToggleModule (ControlCenterUIKit) est déjà chargé dans SpringBoard : résolution
# au chargement, ce qui évite de dépendre de ce framework privé dans le SDK du CI.
GlitchFrameCC_LDFLAGS = -Wl,-undefined,dynamic_lookup
GlitchFrameCC_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk
