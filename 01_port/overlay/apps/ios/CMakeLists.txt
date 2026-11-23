# iOS app target for the Bim! port.
#
# Mirrors apps/linux (an executable linking bim_axmol_app) but produces an app bundle:
# main.mm creates the Bim! application, UIApplicationMain hands control to axmol's
# AxmolAppController, and the shipped assets are copied from the prebuilt asset directory
# into Bim.app.

set(bim_ios_sources
  main.mm
  GameAppController.mm
)

add_executable(bim MACOSX_BUNDLE ${bim_ios_sources})

target_include_directories(bim PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# jsoncpp is a direct dependency of the app (loading_screen reads the sprite sheets'
# metadata), and iscool-core's package does not re-export it, so ask for it here.
find_package(jsoncpp REQUIRED)
target_link_libraries(bim PRIVATE bim_axmol_app JsonCpp::JsonCpp)

set_target_properties(
  bim
  PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Bim!"
    MACOSX_BUNDLE_GUI_IDENTIFIER "bim.app"
    MACOSX_BUNDLE_EXECUTABLE_NAME "Bim"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_INFO_PLIST_OUTPUT_NAME "Info"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "bim.app"
    XCODE_ATTRIBUTE_PRODUCT_NAME "Bim"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "17.0"
    XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "@executable_path/Frameworks @executable_path/../../Frameworks"
    BUILD_RPATH "@executable_path/Frameworks"
    INSTALL_RPATH "@executable_path/Frameworks"
    XCODE_ATTRIBUTE_SWIFT_VERSION ""
    OUTPUT_NAME "Bim"
)

# Assets: the directory produced by the APK's pipeline (see docs/ASSETS.md), copied next to
# the executable so `[NSBundle mainBundle].resourcePath` holds animations.json, the sprite
# sheets, the style JSONs, the fonts, the audio and the gettext catalogues.
if(NOT DEFINED BIM_PREBUILT_ASSETS_DIR)
  message(FATAL_ERROR "BIM_PREBUILT_ASSETS_DIR must point at the prebuilt assets.")
endif()

add_custom_command(
  TARGET bim
  POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E rm -rf "$<TARGET_BUNDLE_DIR:bim>/assets"
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${BIM_PREBUILT_ASSETS_DIR}" "$<TARGET_BUNDLE_DIR:bim>/assets"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${CMAKE_CURRENT_SOURCE_DIR}/LaunchScreen.storyboard"
          "$<TARGET_BUNDLE_DIR:bim>/LaunchScreen.storyboard"
  # The home-screen icon set, generated from the APK's own ic_launcher by
  # 01_port/tools/make-icons.sh. Without these the app installs with a blank icon.
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${CMAKE_CURRENT_SOURCE_DIR}/icons" "$<TARGET_BUNDLE_DIR:bim>"
  # The engine's own compiled shaders (Metal bytecode for this build). The APK ships GLES
  # ones, so these overwrite them name for name.
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${BIM_AXMOL_SHADERS_DIR}" "$<TARGET_BUNDLE_DIR:bim>/assets"
  # OpenAL Soft is a dynamic framework on iOS, so it has to travel inside the bundle.
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:bim>/Frameworks"
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${BIM_OPENAL_FRAMEWORK}" "$<TARGET_BUNDLE_DIR:bim>/Frameworks/soft_oal.framework"
  COMMENT "Copying the game assets into Bim.app"
)

# Bundle directory is where main.mm looks: resourcePath. The assets live in
# Bim.app/assets, so the resource path is Bim.app — keep them one level deeper to avoid
# clashing with the storyboard.
set_target_properties(bim PROPERTIES XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT "YES")
