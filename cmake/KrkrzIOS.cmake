# KrkrzIOS.cmake - アプリバンドル (.app) の設定
#
# app.cmake (gen-config.py 生成) の APP_* 変数を使って、エンジンが作る
# MACOSX_BUNDLE ターゲットに Info.plist / 署名 / アイコン / 案件資材を載せる。

set(KRKRZ_IOS_TEMPLATE_DIR ${CMAKE_CURRENT_LIST_DIR}/../ios)

function(krkrz_platform_target_hook TARGET)
    # 起動画面は Info.plist の UILaunchScreen (iOS 14+) で指定する。
    # storyboard だと ibtool がシミュレータランタイムを要求しビルド環境依存が増えるため使わない。

    # アイコン (gen-config.py が icon 指定から Assets.xcassets を生成した場合のみ)
    set(_xcassets "${MYAPP_DIR}/Assets.xcassets")
    if(EXISTS "${_xcassets}")
        target_sources(${TARGET} PRIVATE ${_xcassets})
        set_source_files_properties(${_xcassets} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        set_target_properties(${TARGET} PROPERTIES
            XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon")
    endif()

    set_target_properties(${TARGET} PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${KRKRZ_IOS_TEMPLATE_DIR}/Info.plist.in"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${APP_BUNDLE_ID}"
        MACOSX_BUNDLE_BUNDLE_NAME "${APP_DISPLAY_NAME}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${APP_VERSION}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${APP_BUILD}"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${APP_BUNDLE_ID}"
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${APP_DEPLOYMENT_TARGET}"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "${APP_DEVICE_FAMILY}"
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${APP_DEVELOPMENT_TEAM}"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development"
        "XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" "-"
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
        XCODE_ATTRIBUTE_SKIP_INSTALL "NO"
        XCODE_ATTRIBUTE_INSTALL_PATH "$(LOCAL_APPS_DIR)"
        XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Release] "dwarf-with-dsym"
        XCODE_GENERATE_SCHEME ON
    )
    if(APP_ENTITLEMENTS)
        set_target_properties(${TARGET} PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${APP_ENTITLEMENTS}")
    endif()

    # 案件資材 (assetPack マージ結果) をバンドル直下へ。
    # SDL_GetBasePath() = バンドル直下なので、data.xp3 / data/startup.tjs がそのまま見つかる。
    # Xcode の POST_BUILD はコード署名より前に走る。
    # バンドル直下には実行ファイル等もあるので --delete はしない
    # (資材を削除した場合の残骸は make clean で消える)。
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND /bin/sh "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../scripts/copy-assets.sh" "${MYAPP_DIR}/assets"
        VERBATIM
    )
endfunction()
