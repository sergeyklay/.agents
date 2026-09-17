#!/bin/sh
set -eu

server_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# npm adds tsx to the child PATH, so resolve NODE_PATH inside that shell.
# shellcheck disable=SC2016
exec npm exec --yes \
  --package=tsx@4.23.13 \
  --package=@modelcontextprotocol/sdk@1.30.0 \
  --package=dotenv@17.4.2 \
  --package=pg@8.23.0 \
  --package=zod@4.5.4 \
  -- sh -c 'NODE_PATH=$(dirname "$(dirname "$(command -v tsx)")") exec tsx "$1"' \
  sh "$server_dir/postgres.ts"
