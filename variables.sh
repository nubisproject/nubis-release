#!/bin/bash

# This is the general variables file

# Start by sourcing the local variables file if it exists
if [ -f ./variables_local.sh ]; then
    source ./variables_local.sh
else
    log_term 0 "You need to set up your 'variables_local.sh' file"
    log_term 0 "Try copying the 'variables_local.sh-dist' file and editing it"
    exit 1
fi

# The nubisproject GitHub orginization
GITHUB_ORGINIZATION='nubisproject'
log_term 3 "GITHUB_ORGINIZATION=${GITHUB_ORGINIZATION}"

# List of repositories that will be excluded form the release
declare -a RELEASE_EXCLUDES=(nubis-accounts-nubis nubis-accounts-webops nubis-ci nubis-elasticsearch nubis-elk nubis-ha-nat nubis-junkheap nubis-mediawiki nubis-meta nubis-proxy nubis-puppet-storage nubis-puppet-nat nubis-puppet-nsm nubis-puppet-mig nubis-puppet-eip nubis-puppet-discovery nubis-puppet-consul_do nubis-puppet-configuration nubis-puppet-envconsul nubis-puppet-consul-replicate nubis-siege nubis-storage nubis-vpc nubis-wrapper )
log_term 3 "RELEASE_EXCLUDES=${RELEASE_EXCLUDES}"

# List of infrastructure projects that need to be rebuilt from nubis-base during a release
declare -a INFRASTRUCTURE_ARRAY=( nubis-ci nubis-consul nubis-dpaste nubis-fluent-collector nubis-jumphost nubis-nat nubis-prometheus nubis-skel )
log_term 3 "INFRASTRUCTURE_ARRAY=${INFRASTRUCTURE_ARRAY}"
