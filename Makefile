export ARCHS = arm64 arm64e
export TARGET := iphone:clang:latest:15.0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlitchFrame

GlitchFrame_FILES = Tweak.x GlitchEngine.m GlitchCompositor.m
GlitchFrame_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
GlitchFrame_FRAMEWORKS = UIKit QuartzCore CoreGraphics

SUBPROJECTS += ccmodule

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
