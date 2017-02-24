#!/bin/bash

testing () {
    echo "testing"
#    get_repositories
#    echo ${REPOSITORY_ARRAY[*]}
#    edit_deploy_templates "$1"
#     _REPOSITORY="nubis-base"
#     _ISSUE_TITLE="Tag v1.4.0 release"
#     _MILESTONE='14'
#     _ISSUE_EXISTS=$(get_release_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_MILESTONE}")
#     if [ $? == 0 ]; then
#         log_term 2 "Release issue exists. Returned: '${_ISSUE_EXISTS}'. Skipping 'file_issue'."
#         log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#     else
#         echo "file_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_BODY}" "${_MILESTONE}""
#     fi

# v0.9.0 v1.1.0 v1.2.0 v1.2.1 v1.2.2 v1.2.3 v1.3.0
local _RELEASE='v1.2.2'

# REPO=${1}
# COUNT=$(( ( RANDOM % 10 )  + 1 ))
# echo "${REPO} one ${COUNT}"
# sleep ${COUNT}
# COUNT=$(( ( RANDOM % 10 )  + 1 ))
# echo "${REPO} two ${COUNT}"
# sleep ${COUNT}
# COUNT=$(( ( RANDOM % 10 )  + 1 ))
# echo "${REPO} three ${COUNT}"
# sleep ${COUNT}
# COUNT=$(( ( RANDOM % 10 )  + 1 ))
# echo "${REPO} four ${COUNT}"
# sleep ${COUNT}
# COUNT=$(( ( RANDOM % 10 )  + 1 ))
# echo "${REPO} five ${COUNT}"
# sleep ${COUNT}

#build_and_release_all "${_RELEASE}" 'skip-release'


}

