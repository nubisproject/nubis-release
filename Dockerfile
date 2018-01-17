# Docker image containing all dependencies for releasing Nubis

# Downloading release of hub from github does not work on alpine linux see:
# https://github.com/github/hub/issues/1645
# As a result, build it on alpine and copy it into the release container
FROM alpine:3.6 AS build-hub
RUN apk add --no-cache \
    bash \
    go=1.8.4-r0 \
    libc-dev=0.7.1-r \
    git=2.13.5-r0
WORKDIR /app
RUN ["/bin/bash", "-c", "set -o pipefail \
    && git clone https://github.com/github/hub.git \
    && cd hub \
    && git fetch --tags \
    && git checkout v2.2.9 \
    && ./script/build " ]


FROM alpine:3.6
WORKDIR /nubis

# Install container dependencies
RUN apk add --no-cache \
    bash \
    curl \
    docker \
    git \
    jq \
    nodejs \
    nodejs-npm \
    ruby \
    ruby-irb \
    ruby-rdoc

# Set up the directory structure for the code and utilities
RUN [ "mkdir", "-p", "/nubis/bin", "/nubis/nubis-release/.repositories", "/root/.config"]

# Do not add a 'v' as pert of the version string (ie: v1.1.3)
#+ This causes issues with extraction due to GitHub's methodology
#+ Where necessary the 'v' is specified in code below
ENV GhiVersion=1.2.0 \
    ChangelogGeneratorVersion=1.14.1

# Install gem dependencies
RUN gem install ghi -v ${GhiVersion}
RUN gem install rake
RUN gem install github_changelog_generator -v ${ChangelogGeneratorVersion}

# Install hub
COPY --from=build-hub /app/hub/bin/hub /nubis/bin/hub

# Clean up apk cache files
RUN rm -f /var/cache/apk/APKINDEX.*

# Copy over nubis-release code
COPY [ "bin/", "/nubis/nubis-release/bin/" ]

# Copy over the nubis-release-wrapper script
COPY [ "nubis/docker/nubis-release-wrapper", "/nubis/nubis-release/" ]

# Create empty gitconfig and git-credentials files
#+ This is for runtime mounting file volumes
RUN touch /root/.gitconfig /root/.git-credentials-seed /root/.config/hub

# Set up the path to include our code and utilities
ENV PATH /nubis/bin:$PATH

# Set the entry-point to the wrapper script
ENTRYPOINT [ "/nubis/nubis-release/nubis-release-wrapper" ]

# Give the people some useful information
CMD [ "help" ]
#CMD [ "/bin/bash" ]
