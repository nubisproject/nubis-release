

# Nubis Release

[![Version](https://img.shields.io/github/release/nubisproject/nubis-release.svg?maxAge=2592000)](https://github.com/nubisproject/nubis-release/releases)
[![Build Status](https://img.shields.io/travis/nubisproject/nubis-release/master.svg?maxAge=2592000)](https://travis-ci.org/nubisproject/nubis-release)
[![Issues](https://img.shields.io/github/issues/nubisproject/nubis-release.svg?maxAge=2592000)](https://github.com/nubisproject/nubis-release/issues)

This tooling is designed for releasing the Nubis project. In general this
tooling should only be used as part of the release process. This tool is not
intended for building AMIs as part of the development process as it modifies a
number of files during the process that are not typically changed during a
development cycle.

The release of a nubis repository is based on a number of assumptions concerning
the repository structure. We use a release branch methodology for the release
process. Further, all nubis repositories contain a 'master' branch, which is
only intended for releases, and a 'develop' branch, where development work is
merged and tested. When all code has landed for a release, the 'develop' branch
is branched into a 'release-vX.X.X' branch. This release branch is where all of
the release work occurs. Once the release steps (including AMI builds) are
complete, a tag is created and a pull request is created against both the
'master' and 'develop' branches. This tooling automatically merges these release
pull requests, completing the release process.

In the variables file exist two arrays, one describing all of the repositories
that will be released only (no AMI build) and one describing all of the
repositories that will have an AMI built and then be released. Any repositories
not expressly listed in these two arrays are not part of the normal release
process. The remaining repositories are either on their own release cycle
(ie: nubis-builder), or are otherwise not released (ie: nubis-jumkheap).

When conducting a normal release all of the release work occurs in one run. If
a patch release is necessary, the release is broken into two steps. First is to
set up the release, which checks out clean copies of all relevant repositories
at a starting point, typically the previous release. Then the release engineer
will make necessary patch changes to code, typically merging in a patch
(feature) branch. Once the code patching is complete the second step, complete
release, happens. This step builds AMIs and releases repositories in the same
manner as the normal release process.

It is important to note that there is no code difference between a normal or
patch release. The same code paths are used in both cases. The only difference
is that during a normal release, there is no pause for code patching between the
two steps.

Most of the functionality is quite obvious, if one is familiar with both
nubis-builder and git. There are a few convenience functions in this tooling
(try release.sh --help). The code itself is generally understandable and should
be consulted for actual methodology, error handling, logic, etcetera.

There are a number of things that can be accomplished with this tooling:

- [Create a normal release](#create-a-normal-release)
- [Create a patch release](#create-a-patch-release)
- [Release a single repository](#release-a-single-repository)
- [Build a single repository](#build-a-single-repository)
- [Build and release a single repository](#build-and-release-a-single-repository)
- [Upload release assets](#upload-release-assets)
- [Create or Close release milestones](#create-or-close-release-milestones)
- [Generate a CSV file of release issues](#generate-a-csv-file-of-release-issues)

## Create a normal release

To create a normal release, start by printing out the release instructions:

```bash
release.sh --instructions
```

Folow the instructions labeled "Normal Release". This follows the basic
work-flow:

1. Build and Release all repositories
1. Generate closed issue list
1. Create a release presentation
1. Send a release announcement
1. Create milestones for the next release
1. Build the AMIs for the next release development cycle

## Create a patch release

To create a patch release, start by printing out the release instructions. You
will notice that this is basically a simplified version of the normal release,
except that the process halts while patches are applied:

```bash
release.sh --instructions
```

Folow the instructions labeled "Patch Release". This follows the basic
work-flow:

1. Set up patch release
1. Apply patches
1. Build and Release all repositories
1. Send a release announcement

## Release a single repository

If you need to release a single repository (no AMI build) you can simply:

```bash
release.sh release [REPOSITORY] [RELEASE]
```

This is useful for testing a release. You should change the
'GITHUB_ORGINIZATION' in 'variables.sh' to your github user. This enables you to
test releases without polluting the official repositories.

## Build a single repository

If you need to build a single repository (AMI build only) you can simply:

```bash
release.sh build [REPOSITORY] [RELEASE]
```

**NOTE**: This should not be used for development builds as it modifies files
that should not be changed during normal development cycles.

This is useful for testing a build. You should change the 'GITHUB_ORGINIZATION'
in 'variables.sh' to your github user. This enables you to test builds without
polluting the official repositories.

## Build and release a single repository

If you need to build and release a single repository you can:

```bash
release.sh build-and-release [REPOSITORY] [RELEASE]
```

This is useful for testing a release. You should change the
'GITHUB_ORGINIZATION' in 'variables.sh' to your github user. This enables you to
test releases without polluting the official repositories.

## Upload release assets

This is part of the normal and patch release process and does not need to be
called manually. This is here in case you need to upload fresh assets during a
development cycle. During the normal release process a future release dev cycle
is started (vX.X.X-dev). Part of this process uploads assets (primarily lambda
functions) to S3. These assets are used by Terraform during account creations
and upgrades. If you are working on these assets and wish to test them, this
function provides a convenient method for doing so:

```bash
release.sh upload-assets [RELEASE]
```

***WARNING***: Use caution with this function as there are no provisions for
preserving existing assets. In other words, you can modify or destroy assets
from the current or previous release with impunity.

**NOTE**: This can take a substantial amount of time. If you only need to update
a single asset, especially in a single region, ask in #nubis-users for a faster
upload method.

## Create or Close release milestones

This is another convenience function that is not typically necessary outside of
the normal release process. This will create, or close, a named milestone
(typically the release number) for all of the repositories in both the release
and build and release arrays.

```bash
release.sh create-milestones [RELEASE]
release.sh close-milestones [RELEASE]
```

## Generate a CSV file of release issues

Another convenience function used as part of the normal release process. This
generates a CSV file consisting of all of the closed issues in a given date
range (normally the release start and end dates). The generated file is placed
in the 'logs/' directory.

```bash
vi ./variables.sh # Update "RELEASE_DATES" variable
release.sh generate-csv [RELEASE]
```

### Fin

That should be all the info you need. If you run into any issue or have any
trouble feel free to reach out to us. We are happy to help and are quite
interested in improving the project in any way we can. We are on irc.mozilla.org
in #nubis-users or you can reach us on the mailing list at
nubis-users[at]googlegroups.com
