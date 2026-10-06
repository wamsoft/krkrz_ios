# 吉里吉里Z iOS 外枠
#
#   make build                    # Simulator 用 Debug ビルド
#   make run                      # Simulator にインストールして起動 (ログを表示)
#   make build SDK=device         # 実機用
#   make xcode                    # 生成した Xcode プロジェクトを開く
#   PROJECT_DIR=/path/to/案件 make build
#
# 案件横断の環境設定 (DEVELOPMENT_TEAM など) は local.mk (gitignore) に書く。

-include local.mk

ifeq ($(VCPKG_ROOT),)
$(error VCPKG_ROOT が未設定です)
endif
BUILD_SYSTEM_DIR := $(realpath $(CURDIR))
PROJECT_DIR ?= $(BUILD_SYSTEM_DIR)

# krkrz_dev の参照先。 既定はこのリポジトリと同じ階層に clone した krkrz_dev
# (KRKRZ_BASE/krkrz_dev と KRKRZ_BASE/krkrz_ios が並ぶ構成)。 環境変数で上書き可。
KRKRZ_BASE ?= $(realpath $(BUILD_SYSTEM_DIR)/..)
ifeq ($(wildcard $(KRKRZ_BASE)/krkrz_dev/src/core/CMakeLists.txt),)
$(error $(KRKRZ_BASE)/krkrz_dev が見つかりません。krkrz_dev をこのリポジトリと同じ階層に clone するか KRKRZ_BASE を指定してください)
endif

export BUILD_SYSTEM_DIR PROJECT_DIR KRKRZ_BASE DEVELOPMENT_TEAM APP_CONFIG_FILE

SDK    ?= simulator
CONFIG ?= Debug

# Simulator はホストの CPU に合わせる (Intel Mac は x86_64, Apple Silicon は arm64)
HOST_ARCH := $(shell uname -m)

ifeq ($(SDK),device)
SYSROOT := iphoneos
ARCH    := arm64
TRIPLET := arm64-ios-krkrz
else ifeq ($(SDK),simulator)
SYSROOT := iphonesimulator
ARCH    ?= $(HOST_ARCH)
ifeq ($(ARCH),x86_64)
TRIPLET := x64-ios-simulator-krkrz
else
TRIPLET := arm64-ios-simulator-krkrz
endif
else
$(error SDK は simulator か device を指定してください)
endif

IOS_BUILD := $(PROJECT_DIR)/build/ios
GEN_DIR   := $(IOS_BUILD)/generated
BUILD_DIR := $(IOS_BUILD)/$(SDK)-$(ARCH)
XCODEPROJ := $(BUILD_DIR)/krkrz_ios.xcodeproj
APP       := $(BUILD_DIR)/krkrz/$(CONFIG)-$(SYSROOT)/krkrz.app

# Simulator (UDID または booted)。 UDID 指定時は未起動なら boot する
# 一覧: xcrun simctl list devices available
SIM_DEVICE ?= booted

# 通常は -target + -sdk で叩く (Xcode 26 の scheme ビルドは destination 解決に
# iOS プラットフォーム (Settings > Components) の導入を要求するため)。
# 実機で DEVICE=<UDID> を指定したときだけ scheme + destination にする
# (自動署名で接続中のデバイスを Team に登録しプロファイルを作らせるのに必要)。
ifneq ($(and $(filter device,$(SDK)),$(DEVICE)),)
XCODEBUILD := xcodebuild -project "$(XCODEPROJ)" -scheme krkrz -configuration $(CONFIG) \
	-destination "id=$(DEVICE)" -allowProvisioningUpdates -allowProvisioningDeviceRegistration
else
XCODEBUILD := xcodebuild -project "$(XCODEPROJ)" -target krkrz -configuration $(CONFIG) \
	-sdk $(SYSROOT) -arch $(ARCH) -allowProvisioningUpdates
endif

.PHONY: all gen configure build run log xcode clean distclean vars bundle-id

all: build

gen:
	python3 -I "$(BUILD_SYSTEM_DIR)/scripts/gen-config.py"

$(XCODEPROJ):
	$(MAKE) configure

configure: gen
	cmake -S "$(BUILD_SYSTEM_DIR)" -B "$(BUILD_DIR)" -G Xcode \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=$(SYSROOT) \
		-DCMAKE_OSX_ARCHITECTURES=$(ARCH) \
		-DCMAKE_TOOLCHAIN_FILE="$(VCPKG_ROOT)/scripts/buildsystems/vcpkg.cmake" \
		-DVCPKG_TARGET_TRIPLET=$(TRIPLET) \
		-DMYAPP_DIR="$(GEN_DIR)" \
		$(CMAKEOPT)

build: gen $(XCODEPROJ)
	$(XCODEBUILD) build

# 起動引数。 REPL=<port> で -replweb=<port> を付ける (repl 有効ビルドのみ)
RUN_ARGS ?=
ifneq ($(REPL),)
RUN_ARGS += -replweb=$(REPL) -replwebidle=no
endif

APP_ID = $(shell python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bundleId"])' "$(or $(APP_CONFIG_FILE),$(PROJECT_DIR)/ios-config.json)")

run: build
ifeq ($(SDK),simulator)
ifneq ($(SIM_DEVICE),booted)
	-xcrun simctl boot "$(SIM_DEVICE)" 2>/dev/null
endif
	open -a Simulator
	xcrun simctl install "$(SIM_DEVICE)" "$(APP)"
	xcrun simctl launch --console-pty --terminate-running-process "$(SIM_DEVICE)" $(APP_ID) $(RUN_ARGS)
else
	xcrun devicectl device install app --device "$(DEVICE)" "$(APP)"
	xcrun devicectl device process launch --console --terminate-existing --device "$(DEVICE)" $(APP_ID) $(RUN_ARGS)
endif

xcode: $(XCODEPROJ)
	open "$(XCODEPROJ)"

clean:
	-$(XCODEBUILD) clean

distclean:
	rm -rf "$(IOS_BUILD)"

vars:
	@echo BUILD_SYSTEM_DIR=$(BUILD_SYSTEM_DIR)
	@echo PROJECT_DIR=$(PROJECT_DIR)
	@echo SDK=$(SDK) CONFIG=$(CONFIG) TRIPLET=$(TRIPLET)
	@echo BUILD_DIR=$(BUILD_DIR)
	@echo APP=$(APP)
	@echo APP_ID=$(APP_ID)
