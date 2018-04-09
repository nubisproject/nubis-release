#!/bin/bash
# shellcheck disable=SC1117
# shellcheck disable=SC2034
# https://github.com/koalaman/shellcheck/wiki/SC2034
#
# This is a collection of functions to test for dependancies
#

test_for_docker () {
    if ! docker --version > /dev/null 2>&1; then
        log_term 0 "ERROR: docker must be installed and on your path!"
        log_term 0 "Try adding the socket and binary to your invocation."
        log_term 0 "docker run -it -v /var/run/docker.sock:/var/run/docker.sock nubis-release"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_ghi () {
    if ! ghi --version > /dev/null 2>&1; then
        log_term 0 "ERROR: ghi must be installed and on your path!"
        log_term 0 "See: https://github.com/stephencelis/ghi"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_github_changelog_generator () {
    if ! github_changelog_generator --version > /dev/null 2>&1; then
        log_term 0 "ERROR: github_changelog_generator must be installed and on your path!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_hub () {
    if ! hub --version > /dev/null 2>&1; then
        log_term 0 "ERROR: hub must be installed and on your path!"
        log_term 0 "See: https://hub.github.com/"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_jq () {
    if ! jq --version > /dev/null 2>&1; then
        log_term 0 "ERROR: jq must be installed and on your path!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_npm () {
    if ! npm --version > /dev/null 2>&1; then
        log_term 0 "ERROR: npm must be installed and on your path!"
        log_term 0 "See: https://www.npmjs.com/get-npm"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

test_for_rvm () {
    if ! rvm --version > /dev/null 2>&1; then
        log_term 0 "\n\nNOTE: rvm is not installed on your path" -e
        log_term 0 "NOTE: try $0 install-rvm\n\n" -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi
}
