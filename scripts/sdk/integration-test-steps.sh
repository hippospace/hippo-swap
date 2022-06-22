#!/bin/zsh

# Example:
#   xargs sh scripts/sdk/integration-test-steps.sh < scripts/sdk/integration-test-steps.args

# 1. start and run local validator
# 2. fund for account
# 3. build json
# 4. tsgen api files into sdk
# 5. sdk mock deploy ... series testing

CURDIR=$(pwd)

usage() {
  echo "Usage: $0 [-a /aptos-core-path] [-h /hippo-path] [-t /tsgen-path]  [-s /sdk-path] [-c /config.file] [-p profile] -r" 1>&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -c | --config-file)
    CONFIG_FILE="$2"
    echo "Config file: $CONFIG_FILE"
    shift
    ;;
  -a | --aptos-core-path)
    APTOS_CORE_PATH="$2"
    echo "Hippo path: $APTOS_CORE_PATH"
    shift
    ;;
  -h | --hippo-path)
    HIPPO_PATH="$2"
    echo "Hippo path: $HIPPO_PATH"
    shift
    ;;
  -t | --tsgen-path)
    TSGEN_PATH="$2"
    echo "TsGen path: $TSGEN_PATH"
    shift
    ;;
  -s | --sdk-path)
    SDK_PATH="$2"
    echo "SDK path: $SDK_PATH"
    shift
    ;;
  -p|--profile)
    PROFILE="$2";
    echo "PROFILE: $PROFILE"
    shift
    ;;
  -r | --replace-sdk)
    COPY_TO_HIPPO=1
    echo "COPY to hippo sdk: $COPY_TO_HIPPO"
    shift
    ;;
  *)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
  shift
done

cd "${HIPPO_PATH}" || exit 1
ACCOUNT_ID=$(yq ".profiles.${PROFILE}.account" .aptos/config.yaml)
sh scripts/validator/start_validator.sh -d "${APTOS_CORE_PATH}" -p "${PROFILE}"
aptos account fund --account "${ACCOUNT_ID}"  --profile v4_local --num-coins 1000000

sh scripts/sdk/hippo-gen.sh -h "${HIPPO_PATH}" -t "${TSGEN_PATH}" -s "${SDK_PATH}" -r

sh scripts/sdk/sdk-integration-tests.sh -s "${SDK_PATH}" -c "${CONFIG_FILE}" -p "${PROFILE}"

cd "${CURDIR}" || exit 1

exit 0
