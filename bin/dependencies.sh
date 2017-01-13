#!/bin/bash
#
# This is a collection of functions to test for dependancies
# Additionally some dependancies can be installed here
#

test_for_ghi () {
    TEST=$(which ghi 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "ghi must be installed and on your path!"
        log_term 0 "See: https://github.com/stephencelis/ghi"
        exit 1
    fi
}

test_for_nubis_builder () {
    TEST=$(which nubis-builder 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "nubis-builder must be installed and on your path!"
        log_term 0 "See: https://github.com/Nubisproject/nubis-builder#builder-quick-start"
        exit 1
    fi
}

test_for_sponge () {
    TEST=$(which sponge 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "sponge must be installed and on your path!"
        log_term 0 "sponge is provided by the 'moreutils' package on ubuntu"
        exit 1
    fi
}

test_for_jq () {
    TEST=$(which jq 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "jq must be installed and on your path!"
        exit 1
    fi
}

test_for_github_changelog_generator () {
    TEST=$(which github_changelog_generator 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "github_changelog_generator must be installed and on your path!"
        exit 1
    fi
}

test_for_rvm () {
    TEST=$(which rvm 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "\n\nNOTE: rvm is not installed on your path" -e
        log_term 0 "NOTE: try $0 install-rvm\n\n" -e
    fi
}

install_rvm (){
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
    \curl -sSL https://get.rvm.io | bash -s stable
    source ~/.rvm/scripts/rvm
    rvm install 2.1
    rvm use 2.1
    sudo ln -s ~/.rvm/rubies/ruby-2.1.8/bin/ruby /usr/bin/ruby2.1
    gem install puppet
    gem install librarian-puppet
    gem install github_changelog_generator
#    gem install ghi
    rvm list
    rvm use 2.1
    gem list
    
    # The gem build is broken at the moment
    #+ This will grab the raw 1.2.0 version and install it in your home bin directory
    curl -sL https://raw.githubusercontent.com/stephencelis/ghi/b3abe43a0d62a50cadc825a12bd1b2e09e8bb059/ghi  > ghi
    chmod 755 ghi
    mv ghi ~/bin
    ghi --version
}
