#!/bin/zsh

## Deploy and start up a brand new localnet validator with faucet apis.
## Required Aptos-core git repo.
## example:
##
##     sh scripts/validator/start_validator.sh -d ~/MoveProjects/aptos-core
##

source_root=$(pwd)

run_validator ()
{
  pwd
  echo "Running"
  output="/tmp/nohup-aptos-node.out"
  CARGO_NET_GIT_FETCH_WITH_CLI=true nohup cargo run -r -p aptos-node -- --test > ${output} 2>&1 &
  echo "Starting up aptos..."
  while true;
   do
     mint_key=$(grep -o 'Aptos root key path: "[^"]*"' "$output" | sed 's/Aptos root key path: "\(.*\)"/\1/')
    if [ -n "${mint_key}" ]; then
      break
    else
      continue
    fi ; done
  echo "Aptos node has been start up..."
  mint_key=$(grep -o 'Aptos root key path: "[^"]*"' "$output" | sed 's/Aptos root key path: "\(.*\)"/\1/')
  echo "Key:"
  echo "${mint_key}"
  mint_output="/tmp/nohup-aptos-mint-faucet.out"
  echo "Starting up aptos mint faucet..."
  nohup cargo run -r --package aptos-faucet -- --chain-id TESTING --mint-key-file-path "${mint_key}" --address 0.0.0.0 --port 8000 --server-url http://127.0.0.1:8080 > ${mint_output} 2>&1 &
  while true;
   do
     test_mint_api_running=$(grep -o 'listening on' "$mint_output")
    if [ -n "${test_mint_api_running}" ]; then
      break
    else
      continue
    fi ;
  done
  echo "Faucet OK..."
}

pgrep 'aptos-node' | xargs kill
pgrep 'aptos-faucet' | xargs kill

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--aptos-core-dir) target="$2"; shift ;;
        -p|--profile) profile="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

echo "Where to deploy: ${target}"
if [ -z "${target}" ]; then
  echo "Usage:"
  echo "Please run command with aptos-core path"
  echo "example:"
  echo "        sh scripts/validator/start_validator.sh -d <the-path-of-aptos-core>"
  exit
fi ;

cd "${target}" || exit
run_validator

cd "${source_root}" || exit

echo "removing config:"
rm -rf .aptos

echo "Current path:"
pwd

echo "Done."
ln -s "${HOME}/.config/aptos/.aptos" .
account_id=$(yq ".profiles.${profile}.account" .aptos/config.yaml)
echo "account id is ${account_id}"
aptos account create --profile "${profile}" --account "${account_id}" --use-faucet
echo "The account_id is :"
account_id_prefixed="0x${account_id}"
echo "${account_id_prefixed}"
cd /tmp || exit
rm -rf aptos-registry
git clone https://github.com/hippospace/aptos-registry.git
cd aptos-registry/move || exit
ln -s "${HOME}/.config/aptos/.aptos" .
aptos move compile --package-dir .
aptos move publish --package-dir . --profile "${profile}"

cd "${source_root}" || exit
aptos move compile --package-dir .
aptos move publish --package-dir . --profile "${profile}"
