# ProjectConfig.mk
# Many parts of the build depend on "$(MTK_PROJECT_FOLDER)/ProjectConfig.mk"
# but we have split it into a combination of different ProjectConfig.mk files.
# These are all include in the device specific ProjectConfig.mk so include that
# here.

include device/amazon/$(MTK_TARGET_PROJECT)/ProjectConfig.mk