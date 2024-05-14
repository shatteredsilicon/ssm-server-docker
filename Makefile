SHELL	= /bin/bash

BUILDDIR	?= /tmp/ssmbuild
VERSION		?=

.PHONY: all
all: docker

.PHONY: docker
docker:
	mkdir -vp $(BUILDDIR)
	./build.sh -b "$(BUILDDIR)" -v "$(VERSION)" -n "shatteredsilicon/ssm-server-${HOSTTYPE}"
