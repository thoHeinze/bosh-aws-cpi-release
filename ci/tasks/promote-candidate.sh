#!/usr/bin/env bash

set -e

: ${AWS_ACCESS_KEY_ID:?}
: ${AWS_SECRET_ACCESS_KEY:?}

source bosh-cpi-src/ci/utils.sh
source /etc/profile.d/chruby.sh
chruby 2.4.4

# Creates an integer version number from the semantic version format
# May be changed when we decide to fully use semantic versions for releases
integer_version=`cut -d "." -f1 release-version-semver/number`
echo $integer_version > promoted/integer_version

cp -r bosh-cpi-src promoted/repo

dev_release=$(echo $PWD/bosh-cpi-release/*.tgz)

pushd promoted/repo
  echo creating config/private.yml with blobstore secrets
  cat > config/private.yml << EOF
---
blobstore:
  provider: s3
  options:
    access_key_id: $AWS_ACCESS_KEY_ID
    secret_access_key: $AWS_SECRET_ACCESS_KEY
EOF

  echo "finalizing CPI release..."
  bosh finalize-release ${dev_release} --version $integer_version

  rm config/private.yml

  git diff | cat
  git add .

  git config --global user.email cf-bosh-eng@pivotal.io
  git config --global user.name CI
  git commit -m "New final release v $integer_version"
popd
