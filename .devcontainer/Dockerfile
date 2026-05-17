# Make sure RUBY_VERSION matches the Ruby version in .ruby-version.
ARG RUBY_VERSION=3.4.8
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Keep Rails reachable from the Bluefin host through forwarded devcontainer ports.
ENV BINDING="0.0.0.0"

USER root

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      default-mysql-client \
      ffmpeg \
      gitleaks \
      gum \
      imagemagick \
      libheif1 \
      libjxl-tools \
      libraw-bin \
      libvips-tools \
      libwebp7 \
      netcat-openbsd \
      openslide-tools \
      poppler-utils \
      sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

USER vscode
