SHELL	= /bin/bash

BUILDDIR		?= /tmp/ssmbuild
VERSION			?=
ENV				?=
SSM_REPO_URL	?=
SSM_REPO_GPGKEY	?=

.PHONY: all
all: docker

.PHONY: docker
docker:
	mkdir -vp $(BUILDDIR)
	./build.sh $(BUILDDIR) $(VERSION)