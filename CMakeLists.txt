cmake_minimum_required(VERSION 3.24)

# ======================================================================
# 吉里吉里Z iOS 外枠
#
# Makefile から Xcode ジェネレータで configure される前提:
#   cmake -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos|iphonesimulator
#         -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
#         -DVCPKG_TARGET_TRIPLET=arm64-ios-krkrz|arm64-ios-simulator-krkrz
#         -DMYAPP_DIR=${PROJECT_DIR}/build/ios/generated
#
# MYAPP_DIR は scripts/gen-config.py が ios-config.json から生成するフォルダ:
#   myapp.cmake   … TVP_PLUGIN_FOLDERS / TVP_PLUGINS / TVP_PLUGINS_STATIC
#   app.cmake     … バンドル ID / バージョン / 向き / グラフィックス方式などの変数
#   assets/       … assetPack.sources をマージしたもの (バンドル直下へコピーされる)
# ======================================================================

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "krkrz_ios: CMAKE_SYSTEM_NAME=iOS で configure してください (make configure を使用)")
endif()

# krkrz_dev の参照先: 環境変数 KRKRZ_BASE、 未設定ならこのリポジトリと同じ階層
if(DEFINED ENV{KRKRZ_BASE} AND NOT "$ENV{KRKRZ_BASE}" STREQUAL "")
    cmake_path(SET KRKRZ_BASE "$ENV{KRKRZ_BASE}")
else()
    cmake_path(SET KRKRZ_BASE NORMALIZE "${CMAKE_CURRENT_SOURCE_DIR}/..")
endif()
if(NOT EXISTS "${KRKRZ_BASE}/krkrz_dev/src/core")
    message(FATAL_ERROR "${KRKRZ_BASE}/krkrz_dev が見つかりません。krkrz_dev をこのリポジトリと同じ階層に clone するか、環境変数 KRKRZ_BASE を指定してください")
endif()
set(KRKRZ_DIR ${KRKRZ_BASE}/krkrz_dev/src/core)
set(PLUGINS_DIR ${KRKRZ_BASE}/krkrz_dev/src/plugins)

if(NOT MYAPP_DIR OR NOT EXISTS "${MYAPP_DIR}/app.cmake")
    message(FATAL_ERROR "MYAPP_DIR (gen-config.py の出力) が見つかりません: '${MYAPP_DIR}'")
endif()
include("${MYAPP_DIR}/app.cmake")
include("${MYAPP_DIR}/myapp.cmake")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${MYAPP_DIR}/app.cmake" "${MYAPP_DIR}/myapp.cmake")

# iOS は dlopen 不可なので全プラグイン static
list(APPEND TVP_PLUGINS_STATIC ${TVP_PLUGINS})
list(REMOVE_DUPLICATES TVP_PLUGINS_STATIC)

list(APPEND TVP_PLUGIN_FOLDERS ${PLUGINS_DIR})
set(TPSTUB_DIR ${KRKRZ_DIR}/tp_stub)
set(NCBIND_DIR ${PLUGINS_DIR}/ncbind)
set(SIMPLEBIND_DIR ${PLUGINS_DIR}/simplebinder)

set(CMAKE_OSX_DEPLOYMENT_TARGET "${APP_DEPLOYMENT_TARGET}" CACHE STRING "" FORCE)

# ----------------------------------------------------
# vcpkg マニフェスト統合 (umbrella と同じ。project() より前に必要)
# ----------------------------------------------------
include(${KRKRZ_DIR}/cmake/MergeVcpkgManifest.cmake)
set(_KRKRZ_VCPKG_SUBDIRS "${KRKRZ_DIR}/external/movie-player")
foreach(_plugin IN LISTS TVP_PLUGINS)
    foreach(_folder IN LISTS TVP_PLUGIN_FOLDERS)
        if(EXISTS "${_folder}/${_plugin}")
            list(APPEND _KRKRZ_VCPKG_SUBDIRS "${_folder}/${_plugin}")
            break()
        endif()
    endforeach()
endforeach()
krkrz_merge_vcpkg_manifest(
    BASE    "${KRKRZ_DIR}/vcpkg.json"
    OUTPUT  "${CMAKE_BINARY_DIR}/vcpkg.json"
    SUBDIRS ${_KRKRZ_VCPKG_SUBDIRS}
    EXCLUDE "movie-player:glew" "movie-player:glfw3"
)
set(VCPKG_MANIFEST_DIR "${CMAKE_BINARY_DIR}" CACHE PATH "" FORCE)
set(VCPKG_OVERLAY_TRIPLETS "${CMAKE_CURRENT_SOURCE_DIR}/triplets" CACHE PATH "" FORCE)
# libvpx: iOS Simulator 対応の overlay (本家 port は simulator 向けにビルドできない)
set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_SOURCE_DIR}/vcpkg-ports" CACHE PATH "" FORCE)

project(krkrz_ios C CXX OBJC OBJCXX)

# ----------------------------------------------------
# krkrz setup
# ----------------------------------------------------

set(KRKRZ_DEFINES_PLATFORM
    # Android 外枠と同じくケース無視 + ローカルファイルは大文字小文字を区別
    TVP_NO_NORMALIZE_PATH
    TVP_AUTOPATH_IGNORECASE
    TVP_LOCALFILE_FORCE_CASESENSITIVE
    TVP_DONT_CLEAR_AUTOPATH_CACHE
    # iOS は CoreAudio / AVFoundation を静的リンクする
    MA_NO_RUNTIME_LINKING
)
set(KRKRZ_LIB_PLATFORM
    "-framework AVFoundation"
    "-framework AudioToolbox"
    "-framework CoreAudio"
    # HarfBuzz の CoreText shaper (Apple では既定で有効)
    "-framework CoreText"
    "-framework CoreGraphics"
    "-framework CoreFoundation"
)

option(KRKRZ_ENABLE_DAP "" OFF)
option(KRKRZ_USE_LOGCORE "" OFF)

# REPL: ブラウザ REPL (-replweb, HTTP+SSE) だけを有効化する (console REPL は端末が無いので不要)。
# 起動引数 -replweb=<port> を渡したときだけ待ち受ける。全 IF (IPv6+IPv4) で待ち受けるので
# Simulator は http://127.0.0.1:<port>/、実機は USB 経由の http://<端末名>.coredevice.local:<port>/
# から繋がる。ios-config.json の "repl": false (配布ビルド) では REPL を一切含めない。
if(APP_REPL)
    set(KRKRZ_REPL OFF CACHE BOOL "" FORCE)
    set(KRKRZ_REPL_FILE OFF CACHE BOOL "" FORCE)
    set(KRKRZ_REPL_WEB ON CACHE BOOL "" FORCE)
    set(KRKRZ_REPL_WEB_BIND_ANY ON CACHE BOOL "" FORCE)
else()
    set(KRKRZ_REPL OFF CACHE BOOL "" FORCE)
    set(KRKRZ_REPL_FILE OFF CACHE BOOL "" FORCE)
    set(KRKRZ_REPL_WEB OFF CACHE BOOL "" FORCE)
endif()
message(STATUS "[krkrz_ios] repl=${APP_REPL}")

# 配布ビルド (make archive / ipa): エンジンの量産設定 MASTER を有効にする
# (REPL / 統計 / メモリオーバーレイ等をすべて除外、ログ既定 WARNING)
if(APP_DIST)
    set(MASTER ON CACHE BOOL "" FORCE)
else()
    set(MASTER OFF CACHE BOOL "" FORCE)
endif()
message(STATUS "[krkrz_ios] dist=${APP_DIST} MASTER=${MASTER}")

# Archive にアプリ以外 (静的ライブラリ) を含めない。アプリ本体は KrkrzIOS.cmake で NO に戻す。
# (含まれると Xcode が «Generic Xcode Archive» 扱いにして ipa 書き出しに失敗する)
set(CMAKE_XCODE_ATTRIBUTE_SKIP_INSTALL YES)
option(KRKRZ_BUILD_TESTS "" OFF)
option(KRKRZ_USE_ELEMENTS "" ON)
option(KRKRZ_USE_A11Y "" OFF)

# グラフィックス方式 (ios-config.json の graphics、 既定 gles)
#   gles  : OpenGL ES (EAGL) を有効化し ogl / sdlogl DrawDevice を使う (Android / macOS と同じ)
#   metal : SDL_Renderer (Metal) の sdl DrawDevice のみ (GL 系機能は使えない)
if(APP_GRAPHICS STREQUAL "gles")
    set(KRKRZ_USE_OPENGL ON CACHE BOOL "" FORCE)
    list(APPEND KRKRZ_DEFINES_PLATFORM GLES_SILENCE_DEPRECATION)
    list(APPEND KRKRZ_LIB_PLATFORM "-framework OpenGLES")
else()
    set(KRKRZ_USE_OPENGL OFF CACHE BOOL "" FORCE)
endif()
message(STATUS "[krkrz_ios] graphics=${APP_GRAPHICS} KRKRZ_USE_OPENGL=${KRKRZ_USE_OPENGL}")

# ----------------------------------------------------
# SDL3: 版固定・静的リンク (core 側の FetchContent(main) を回避)
# ----------------------------------------------------
include(FetchContent)
set(KRKRZ_IOS_SDL_TAG "release-3.4.4" CACHE STRING "SDL3 git tag")
FetchContent_Declare(SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG ${KRKRZ_IOS_SDL_TAG}
    GIT_SHALLOW TRUE
)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(SDL3)

# ----------------------------------------------------
# エンジン本体
# ----------------------------------------------------
# アプリバンドル設定はエンジンがターゲット (krkrz) を作った直後に
# krkrz_platform_target_hook() から呼ばれる (POST_BUILD は同一ディレクトリ限定のため)
include(cmake/KrkrzIOS.cmake)

include(${KRKRZ_BASE}/krkrz_dev/cmake/CommonExternals.cmake)
add_subdirectory(${KRKRZ_DIR} ${CMAKE_CURRENT_BINARY_DIR}/krkrz)
