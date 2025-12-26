#!/bin/bash

# ?????IPA ??
# ??: ./build_unsigned_ipa.sh

set -e

# ????
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}??????? IPA${NC}"
echo -e "${GREEN}======================================${NC}"

# ??
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="ReadApp"
SCHEME="ReadApp"
CONFIGURATION="Release"
BUILD_DIR="${SCRIPT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
IPA_DIR="${BUILD_DIR}/ipa"
IPA_NAME="${PROJECT_NAME}_unsigned.ipa"

# ?????
echo -e "
${YELLOW}?? 1/5: ?????...${NC}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${IPA_DIR}"

# ?? Archive
echo -e "
${YELLOW}?? 2/5: ?? Archive...${NC}"
xcodebuild archive     -project "${SCRIPT_DIR}/${PROJECT_NAME}.xcodeproj"     -scheme "${SCHEME}"     -configuration "${CONFIGURATION}"     -archivePath "${ARCHIVE_PATH}"     -destination "generic/platform=iOS"     CODE_SIGN_IDENTITY=""     CODE_SIGNING_REQUIRED=NO     CODE_SIGNING_ALLOWED=NO     AD_HOC_CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo -e "${RED}Archive ????${NC}"
    exit 1
fi

# ?? Payload ??
echo -e "
${YELLOW}?? 3/5: ?? Payload ??...${NC}"
PAYLOAD_DIR="${IPA_DIR}/Payload"
mkdir -p "${PAYLOAD_DIR}"

# ?? .app ??
echo -e "
${YELLOW}?? 4/5: ??????...${NC}"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}??? .app ??: ${APP_PATH}${NC}"
    exit 1
fi

cp -r "${APP_PATH}" "${PAYLOAD_DIR}/"

# ??? IPA
echo -e "
${YELLOW}?? 5/5: ?? IPA...${NC}"
cd "${IPA_DIR}"
zip -r "../${IPA_NAME}" Payload
cd - > /dev/null

# ??????
rm -rf "${IPA_DIR}"

# ??
if [ -f "${BUILD_DIR}/${IPA_NAME}" ]; then
    IPA_SIZE=$(du -h "${BUILD_DIR}/${IPA_NAME}" | cut -f1)
    echo -e "
${GREEN}======================================${NC}"
    echo -e "${GREEN}? ????${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "IPA ??: ${BUILD_DIR}/${IPA_NAME}"
    echo -e "????: ${IPA_SIZE}"
    echo -e "
${YELLOW}??:${NC}"
    echo -e "1. ?????? IPA ??"
    echo -e "2. ?????????????????????????????"
    echo -e "3. ??? Xcode ????????????"
else
    echo -e "
${RED}? ????${NC}"
    exit 1
fi
