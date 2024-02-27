SHELL	= /bin/bash

BUILDDIR	?= /tmp/ssmbuild
VERSION		?= 9.4.1

.PHONY: all
all: docker

.PHONY: docker
docker:
	mkdir -vp $(BUILDDIR)
	./build.sh $(BUILDDIR) $(VERSION)