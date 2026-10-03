ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AimAssist

AimAssist_FILES = AimAssist.m
AimAssist_FRAMEWORKS = UIKit Foundation
AimAssist_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/library.mk
