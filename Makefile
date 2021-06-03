################################################################################
# Configuration
################################################################################
# Load .env from Makefile
ifneq (,$(wildcard ./.env))
	include .env
	export
endif
# Load the value of the ruby version beign used as an environment variable
RUBY_VERSION=$(shell cat .ruby-version)
# Set the current working dir
PWD=$(shell pwd)
# Set the GEM directory
GEM_HOME=/usr/local/bundle
# Set the default Docker Network
DOCKER_NETWORK?=bridge
################################################################################
# Target: clear
# Clear the terminal.
################################################################################
.PHONY: clear
clear:
	clear
################################################################################
# Target: bundle
# Allows to run custom `bundle` commands inside the `build` application.
# Example: make bundle ARGS="locak --update"
################################################################################
.PHONY: run
run:
	@echo "${STAGE} - $(CMD)"
	@docker run --rm -ti \
		-v ${PWD}:/usr/src/myapp \
		-w /usr/src/myapp \
		--network ${DOCKER_NETWORK} \
		--env-file ./.env \
		${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION}-${STAGE} $(CMD)
################################################################################
# Target: exec
# Runs a container from the created image and executes into it.
# Can be used to troubleshoot problems inside the image.
################################################################################
.PHONY: exec
exec: clear
	@echo docker exec --it ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION} /bin/sh
	@docker run --rm -ti \
		-v ${PWD}:/usr/src/myapp \
		--env-file ./.env \
		${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION} /bin/sh
################################################################################
# Target: pre-compile
# Pre-compiles gems and static assets
################################################################################
.PHONY: pre-compile
pre-compile: clear build-image
	@make run STAGE='build' CMD='bundle _2.2.17_ install --jobs=4 --retry=3'
	@make run STAGE='build' CMD='bundle _2.2.17_ exec rake assets:precompile'
################################################################################
# Target: test
# Pre-compiles gems and static assets
################################################################################
.PHONY: test
test: clear test-image
	@make run STAGE='test' CMD='bundle _2.2.17_ install --jobs=4 --retry=3'
	@make run STAGE='test' CMD='bundle _2.2.17_ exec rake test'
################################################################################
# Target: release
# Creates a new release of the project.
################################################################################
.PHONY: release
release: clear test pre-compile build
################################################################################
# Target: build
# Builds a new image
################################################################################
build:
	@make hadolint && \
	DOCKER_BUILDKIT=1 docker build -t ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION} \
		--build-arg RUBY_VERSION=${RUBY_VERSION} \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		--build-arg USER=${USER} \
		--build-arg UID=${UID} \
		--build-arg GID=${GID} \
		.
################################################################################
# Target: test-image
# Run the tests inside a new version of the image. It will be tagged with the
# current version of the project. The base image will use the version of Ruby
# defined on the `.ruby-version` file at the root of this project.
################################################################################
.PHONY: test-image
test-image: clear
	@DOCKER_BUILDKIT=1 docker build -t ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION}-test \
		--target=test \
		--build-arg RUBY_VERSION=${RUBY_VERSION} \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		--build-arg USER=${USER} \
		--build-arg UID=${UID} \
		--build-arg GID=${GID} \
		.
################################################################################
# Target: build-image
# Creates a build image to precompile assets
################################################################################
.PHONY: build-image
build-image: clear
	@DOCKER_BUILDKIT=1 docker build -t ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION}-build \
		--target=build \
		--build-arg RUBY_VERSION=${RUBY_VERSION} \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		--build-arg USER=${USER} \
		--build-arg UID=${UID} \
		--build-arg GID=${GID} \
		.
################################################################################
# Target: grype
# Runs grype over the built image
################################################################################
.PHONY: grype
grype:
	@grype ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION} -o table
################################################################################
# Target: hadolint
# Runs hadolint over the built image
################################################################################
.PHONY: hadolint
hadolint:
	@hadolint Dockerfile
################################################################################
# Target: scan
# Scan the image for known vulnerabilities.
################################################################################
.PHONY: scan
scan: clear
	docker scan ${ORGANIZATION}/${PROJECT_NAME}:${PROJECT_VERSION}
################################################################################
# Target: postgres
# Helper function to boot up just the PostgreSQL database defined in the
# docker-compose file.
################################################################################
.PHONY: postgres
postgres: clear
	docker compose up -d --no-build postgres
	@sleep 30
################################################################################
# Target: db-migrate
# Run the `rake db:migrate` task from the built image.
################################################################################
.PHONY: db-migrate
db-migrate: clear
	@make run DOCKER_NETWORK=${PROJECT_NAME} STAGE='build' CMD='bundle _2.2.17_ exec rake db:migrate'

################################################################################
# Target: db-seed
# Run the `rake db:seed` task from the built image.
################################################################################
.PHONY: db-seed
db-seed: clear
	@make run DOCKER_NETWORK=${PROJECT_NAME} STAGE='build' CMD='bundle _2.2.17_ exec rake db:seed'

################################################################################
# Target: setup
# Starts up a PostgreSQL, Redis, and App container to test the application
# locally.
################################################################################
.PHONY: setup
setup: clear postgres db-migrate db-seed up
################################################################################
# Target: up
# Runs docker-compose up
################################################################################
.PHONY: up
up: clear
	docker compose up -d --no-build
################################################################################
# Target: down
# Runs docker-compose down
################################################################################
.PHONY: down
down: clear
	docker compose down
################################################################################
# Target: teardown
# Destroys the running Docker Compose instance, deleting all networks and
# volumes.
################################################################################
.PHONY: teardown
teardown: clear
	docker compose down -v
################################################################################
# Target: certificates folder
# Creates the `./certificates` folder.
################################################################################
.PHONY: certificates-folder
certificates-folder:
	mkdir -p ./certificates
################################################################################
# Target: ca
# Creates a local CA.
# To use this CA in your system, you need to add them to your OS and configure
# to be trusted by your system. Please refer to your OS's documentation to see
# how to do this.
################################################################################
.PHONY: ca
ca: clear certificates-folder
	openssl req \
		-x509 \
		-nodes \
		-new \
		-sha256 \
		-days 1024 \
		-newkey rsa:2048 \
		-keyout ./certificates/ca.key \
		-out ./certificates/ca.pem \
		-subj "/C=US/CN=Localhost_CA"
	openssl x509 -outform pem -in ./certificates/ca.pem -out ./certificates/ca.crt
################################################################################
# Target: certificates
# Creates a local certificate validated by the CA created with the `make ca`
# task. The certificate will be valid for the domain configured on the
# environment variable `DOMAIN` and for `localhost`.
################################################################################
define DOMAINS_EXT
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = ${DOMAIN}
endef
export DOMAINS_EXT
.PHONY: certificates
certificates: clear certificates-folder
	echo "$$DOMAINS_EXT" > ./certificates/domains.ext
	openssl req \
		-new \
		-nodes \
		-newkey rsa:2048 \
		-keyout ./certificates/localhost.key \
		-out ./certificates/localhost.csr \
		-subj "/C=UY/ST=Montevideo/L=Montevideo/O=Localhost-Certificates/CN=localhost.local"
	openssl x509 \
		-req \
		-sha256 \
		-days 1024 \
		-in ./certificates/localhost.csr \
		-CA ./certificates/ca.pem \
		-CAkey ./certificates/ca.key \
		-CAcreateserial \
		-extfile ./certificates/domains.ext \
		-out ./certificates/localhost.crt
