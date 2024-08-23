SHELL	= /bin/bash

BUILDDIR	?= /tmp/ssmbuild
VERSION		?= unknown
INSTALLREPO	?= ssm-dev

.PHONY: all
all: docker

.PHONY: docker
docker:
	mkdir -vp $(BUILDDIR)
	./build.sh -b "$(BUILDDIR)" -v "$(VERSION)" -n "shatteredsilicon/ssm-server-$(shell uname -p)" -r "$(INSTALLREPO)"

.PHONY: clean
clean:
	rm -rf $(BUILDDIR)/{results,docker-slim} $(BUILDDIR)/ssm-server*
