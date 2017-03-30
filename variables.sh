#!/bin/bash

# This is the general variables file

# The GitHub organization hosting the Nubis repositories
GITHUB_ORGINIZATION='nubisproject'
log_term 3 "GITHUB_ORGINIZATION=${GITHUB_ORGINIZATION}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# List of repositories that should be explicitly excluded form the release
# It is not necessary to list anything here, only repositories explicitly listed in release or build arrays will be released
# This is intended as a convenience to temporarily exclude repositories from a release, generally for testing
declare -a EXCLUDE_REPOSITORIES=(nubis-accounts-nubis nubis-accounts-webops nubis-builder nubis-ha-nat nubis-junkheap nubis-mediawiki nubis-meta nubis-puppet-storage nubis-puppet-nat nubis-puppet-nsm nubis-puppet-mig nubis-puppet-eip nubis-puppet-discovery nubis-puppet-consul_do nubis-puppet-configuration nubis-puppet-envconsul nubis-puppet-consul-replicate nubis-storage nubis-vpc )
log_term 3 "EXCLUDE_REPOSITORIES=${EXCLUDE_REPOSITORIES[*]}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# List of repositories that will be released for the release which do not require an AMI build
# It is not necessary to include repositories here that will be built, they are automatically released
declare -a RELEASE_REPOSITORIES=( nubis-bastionsshkey nubis-deploy nubis-docs nubisproject.github.io nubis-stacks nubis-terraform )
log_term 3 "RELEASE_REPOSITORIES=${RELEASE_REPOSITORIES[*]}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# List of repositories that need to be built from nubis-base and released during a release
# nubis-base is always built and does not need to be specifyed here
declare -a BUILD_REPOSITORIES=( nubis-ci nubis-consul nubis-db-admin nubis-dpaste nubis-fluent-collector nubis-jumphost nubis-nat nubis-prometheus nubis-skel )
log_term 3 "BUILD_REPOSITORIES=${BUILD_REPOSITORIES[*]}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# Dates for this release. This is only used for generating the list of issues which were closed during this time window
RELEASE_DATES="2016-12-21..2017-03-24"
log_term 3 "RELEASE_DATES=${RELEASE_DATES}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# Finish by sourcing the local variables file if it exists
# Tgis allows that file to override any varables in this file
if [ -f ./variables_local.sh ]; then
    source ./variables_local.sh
else
    log_term 0 "You need to set up your 'variables_local.sh' file"
    log_term 0 "Try copying the 'variables_local.sh-dist' file and editing it"
    exit 1
fi
