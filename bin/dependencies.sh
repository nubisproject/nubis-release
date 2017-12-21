#!/bin/bash
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

install_rvm (){
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
    curl -sSL https://get.rvm.io | bash -s stable
    # https://github.com/koalaman/shellcheck/wiki/SC1090
    # shellcheck disable=SC1090
    source ~/.rvm/scripts/rvm
    rvm install 2.1.10
    rvm use 2.1
    [[ -h /usr/bin/ruby2.1 ]] && sudo unlink /usr/bin/ruby2.1
    sudo ln -s ~/.rvm/rubies/ruby-2.1.10/bin/ruby /usr/bin/ruby2.1
    gem install puppet
    gem install librarian-puppet
    # Need to pin github_changelog_generatorat an older version which depends on rack (for ruby v2.1.10)
    # Rack is not version pinned so we need to manually install it at an older version as well
    gem install --version 1.6.4 rack
    gem install --version 1.13.0 github_changelog_generator
    gem install ghi
    rvm list
    rvm use 2.1
    gem list

    # The gem build is broken at the moment for v2.1.8 (seems to work now in v2.1.10)
    #+ This will grab the raw 1.2.0 version and install it in your home bin directory
#    curl -sL https://raw.githubusercontent.com/stephencelis/ghi/b3abe43a0d62a50cadc825a12bd1b2e09e8bb059/ghi  > ghi
#    chmod 755 ghi
#    mv ghi ~/bin
#    ghi --version


}
