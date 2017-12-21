#!/bin/bash
# shellcheck disable=SC2034

# This is the general variables file

# Set the version of the builder docker container
NUBIS_DOCKER_BUILDER_VERSION="v1.0.2"
log_term 2 "NUBIS_DOCKER_BUILDER_VERSION=${NUBIS_DOCKER_BUILDER_VERSION}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# Path to the location to clone git repositories
# Defaults to the location of "$0/.repositories" which is in .gitignore
REPOSITORY_PATH="$(dirname "$(readlink -f "$0")")/../.repositories"
log_term 2 "REPOSITORY_PATH=${REPOSITORY_PATH}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# The GitHub organization hosting the Nubis repositories
GITHUB_ORGINIZATION='nubisproject'
log_term 3 "GITHUB_ORGINIZATION=${GITHUB_ORGINIZATION}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

# The list of regions to copy AMIs to after successful build
AMI_COPY_REGIONS='ap-northeast-1,ap-northeast-2,ap-southeast-1,ap-southeast-2,eu-central-1,eu-west-1,sa-east-1,us-east-1,us-west-1,us-west-2'
log_term 3 "AMI_COPY_REGIONS=${AMI_COPY_REGIONS}"
log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
