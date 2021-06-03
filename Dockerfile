ARG RUBY_VERSION
ARG ALPINE_VERSION=3.13

###############################################################################
# Stage 1 - Base Image
###############################################################################
FROM ruby:$RUBY_VERSION-alpine$ALPINE_VERSION AS base

ARG UID=1000
ARG GID=1000
ARG USER=rails

# Installed dependencies used in the build and production image
RUN apk add --no-cache \
  postgresql-client=13.3-r0 \
  tzdata=2021a-r0 \
  build-base=0.5-r2 \
  postgresql-dev=13.3-r0 \
  apk-tools=2.12.5-r0 \
  && gem install bundler -v 2.2.17 \
  && addgroup -g "$GID" "$USER" && adduser -D -u "$UID" -G "$USER" "$USER" \
  && rm -vrf /var/cache/apk/* \
  && unset BUNDLE_PATH \
  && unset BUNDLE_BIN

WORKDIR /usr/src/myapp

USER $USER
###############################################################################
# Stage 2 - Test Image
###############################################################################
FROM base AS test

USER root

RUN apk add --no-cache \
  sqlite=3.34.1-r0 \
  sqlite-dev=3.34.1-r0 \
  nodejs=14.16.1-r1 \
  yarn=1.22.10-r0 \
  && rm -vrf /var/cache/apk/*

ENV RAKE_ENV=test
ENV RAILS_ENV=test
ENV NODE_ENV=test
ENV DATABASE_URL=sqlite3:////usr/src/myapp/db/test.sqlite3

ARG USER=rails
USER $USER

###############################################################################
# Stage 3 - Build Image
###############################################################################
FROM base AS build

USER root

RUN apk add --no-cache \
  nodejs=14.16.1-r1 \
  yarn=1.22.10-r0 \
  && rm -vrf /var/cache/apk/*

ENV RAKE_ENV=production
ENV RAILS_ENV=production
ENV NODE_NEV=production
ENV BUNDLE_WITHOUT=development:test

ARG USER=rails

RUN chown -R $USER: /usr/local/bundle \
  && chmod -R u+w /usr/local/bundle

USER $USER
###############################################################################
# Stage 4 - Final Image
###############################################################################
FROM base

USER root

ARG USER=rails
ARG SECRET_KEY_BASE

ENV RAKE_ENV=production
ENV RAILS_ENV=production
ENV NODE_NEV=production
ENV BUNDLE_WITHOUT=development:test
ENV BUNDLE_PATH=vendor/cache

COPY --chown=$USER . .

RUN chown -R $USER: /usr/local/bundle \
  && chmod -R u+w /usr/local/bundle

# Install assets
RUN bundle _2.2.17_ install --local --jobs=4 --retry=3 \
  && rm -Rf /usr/src/myapp/node_modules \
  && rm -Rf /usr/src/myapp/db/*.sqlite3 \
  && rm -Rf /usr/src/myapp/tmp/cache \
  && rm -Rf /usr/local/bundle/cache

USER $USER

CMD ["bundle", "_2.2.17_", "exec", "puma", "-C", "./config/puma.rb"]