# Docker image containing all dependencies for releasing Nubis

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
    nodejs-npm

# Install build dependencies
RUN apk add --no-cache --virtual .build-dependencies \
    ruby \
    ruby-irb \
    ruby-rdoc \
    tar \
    unzip

# Set up the directory structure for the code and utilities
RUN [ "mkdir", "-p", "/nubis/bin", "/nubis/nubis-release" ]

# Do not add a 'v' as pert of the version string (ie: v1.1.3)
#+ This causes issues with extraction due to GitHub's methodology
#+ Where necessary the 'v' is specified in code below
ENV GhiVersion=1.2.0 \
    ChangelogGeneratorVersion=1.14.1 \
    HubVersion=2.2.9

# Install gem dependencies
RUN gem install ghi -v ${GhiVersion}
RUN gem install rake
RUN gem install github_changelog_generator -v ${ChangelogGeneratorVersion}

# Install hub
RUN ["/bin/bash", "-c", "set -o pipefail \
    && curl --silent -L https://github.com/github/hub/releases/download/v${HubVersion}/hub-linux-amd64-${HubVersion}.tgz \
    | tar --extract --gunzip --directory=/nubis \
    && cp /nubis/hub-linux-amd64-${HubVersion}/bin/hub /nubis/bin/hub \
    && rm -rf /nubis/hub-linux-amd64-${HubVersion}" ]

# Cleanup build dependencies
RUN apk del --no-cache .build-dependencies

# Clean up apk cache files
RUN rm -f /var/cache/apk/APKINDEX.* .build-dependencies

# Copy over nubis-release code
COPY [ "bin/", "/nubis/nubis-release/bin/" ]

# Copy over the nubis-release-wrapper script
COPY [ "nubis/docker/nubis-release-wrapper", "/nubis/nubis-release/" ]

# Set up the path to include our code and utilities
ENV PATH /nubis/bin:$PATH

# Set the entry-point to the wrapper script
ENTRYPOINT [ "/nubis/nubis-release/nubis-release-wrapper" ]

# Give the people some useful information
CMD [ "help" ]
#CMD [ "/bin/bash" ]
