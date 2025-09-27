#!/usr/bin/make -f

PROJECT_NAME := bananapeel
# Prefer version from VERSION file; fallback to 1.0.0 if missing
VERSION ?= $(shell sed -n '1p' VERSION 2>/dev/null || echo 1.0.0)
DESTDIR ?=
PREFIX ?= /usr
BINDIR := $(DESTDIR)$(PREFIX)/bin
SYSCONFDIR := $(DESTDIR)/etc
DATADIR := $(DESTDIR)$(PREFIX)/share

.PHONY: all clean install uninstall package-prep-deb package-prep-rpm package-deb package-rpm package-freebsd test

all:
	@echo "No compilation needed - shell scripts only"
	@echo "Run 'make install' to install the tools"

install:
	@echo "Installing $(PROJECT_NAME)..."
	install -d $(BINDIR)
	install -d $(SYSCONFDIR)/$(PROJECT_NAME)
	install -d $(DATADIR)/$(PROJECT_NAME)/docs
	install -d $(SYSCONFDIR)/logrotate.d

	# Install scripts
	for script in scripts/setup/*.sh scripts/maintenance/*.sh; do \
		[ -f "$$script" ] && install -m 755 "$$script" $(BINDIR)/ || true; \
	done

	# Install canonical automation script for reuse by setup tools
	if [ -f scripts/automation/tripwire-auto-update.sh ]; then \
		install -d $(DATADIR)/$(PROJECT_NAME); \
		install -m 644 scripts/automation/tripwire-auto-update.sh $(DATADIR)/$(PROJECT_NAME)/tripwire-auto-update.sh; \
	fi

	# Install shared shell library
	if [ -f scripts/lib/bananapeel-lib.sh ]; then \
		install -d $(DATADIR)/$(PROJECT_NAME); \
		install -m 644 scripts/lib/bananapeel-lib.sh $(DATADIR)/$(PROJECT_NAME)/bananapeel-lib.sh; \
	fi

	# Install tripwire wrapper for secure sudo access (standardize on /usr/local)
	if [ -f scripts/wrappers/tripwire-wrapper.sh ]; then \
		install -d $(DESTDIR)/usr/local/lib/$(PROJECT_NAME); \
		install -m 755 scripts/wrappers/tripwire-wrapper.sh $(DESTDIR)/usr/local/lib/$(PROJECT_NAME)/tripwire-wrapper; \
	fi

	# Install sample configuration to /usr/share for reference
	if [ -f config/bananapeel.conf.sample ]; then \
		install -d $(DATADIR)/$(PROJECT_NAME); \
		install -m 644 config/bananapeel.conf.sample $(DATADIR)/$(PROJECT_NAME)/bananapeel.conf.sample; \
	fi

	# Install other configuration files (APT hooks, etc.)
	for conf in config/*; do \
		[ -f "$$conf" ] && [ "$$(basename $$conf)" != "bananapeel.conf.sample" ] && \
		install -m 644 "$$conf" $(SYSCONFDIR)/$(PROJECT_NAME)/ || true; \
	done

	# Install logrotate configuration
	if [ -f config/logrotate.bananapeel ]; then \
		install -m 644 config/logrotate.bananapeel $(SYSCONFDIR)/logrotate.d/bananapeel; \
	fi

	# Install documentation
	for doc in docs/*; do \
		[ -f "$$doc" ] && install -m 644 "$$doc" $(DATADIR)/$(PROJECT_NAME)/docs/ || true; \
	done

	# Create bananapeel-status symlink to tripwire-summary.sh
	# Use runtime absolute target (exclude DESTDIR) so packaged link is valid
	ln -sf $(PREFIX)/bin/tripwire-summary.sh $(BINDIR)/bananapeel-status

uninstall:
	@echo "Uninstalling $(PROJECT_NAME)..."
	rm -rf $(SYSCONFDIR)/$(PROJECT_NAME)
	rm -rf $(DATADIR)/$(PROJECT_NAME)
	rm -f $(SYSCONFDIR)/logrotate.d/bananapeel
	rm -f /usr/local/lib/$(PROJECT_NAME)/tripwire-wrapper
	-rmdir /usr/local/lib/$(PROJECT_NAME) 2>/dev/null || true
	# Remove bananapeel-status symlink
	rm -f $(BINDIR)/bananapeel-status
	# Remove installed scripts
	for script in scripts/setup/*.sh scripts/maintenance/*.sh; do \
		[ -f "$(BINDIR)/$$(basename $$script)" ] && rm -f "$(BINDIR)/$$(basename $$script)" || true; \
	done

clean:
	rm -rf build/*
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete

test:
	@echo "Running tests..."
	@if [ -d "tests" ] && [ -n "$$(ls -A tests)" ]; then \
		bash tests/run_tests.sh; \
	else \
		echo "No tests found"; \
	fi

test-functional:
	@echo "Running functional tests..."
	@# Ensure mocks and test scripts are executable
	@chmod +x tests/mocks/* tests/functional/*.sh 2>/dev/null || true
	@# Run automation tests with proper error handling
	@if [ -x "tests/functional/test_automation.sh" ]; then \
		set -e; \
		cd $(shell pwd) && bash tests/functional/test_automation.sh; \
	else \
		echo "Functional test script not found or not executable"; \
		exit 1; \
	fi
	@# Run installer migration path test
	@if [ -x "tests/functional/test_installer_migration_path.sh" ]; then \
		echo "Running installer migration path test..."; \
		cd $(shell pwd) && bash tests/functional/test_installer_migration_path.sh; \
	else \
		echo "Installer migration path test not found or not executable"; \
	fi
	@# Run status extensions tests
	@if [ -x "tests/functional/test_status_extensions.sh" ]; then \
		echo "Running status extensions tests..."; \
		cd $(shell pwd) && bash tests/functional/test_status_extensions.sh; \
	else \
		echo "Status extensions test script not found or not executable"; \
	fi
	@# Run user migration tests
	@if [ -x "tests/functional/test_user_migration.sh" ]; then \
		echo "Running user migration tests..."; \
		chmod +x scripts/setup/migrate-service-user.sh 2>/dev/null || true; \
		cd $(shell pwd) && bash tests/functional/test_user_migration.sh; \
	else \
		echo "User migration test script not found or not executable"; \
	fi
	@# Run deprecation warning tests
	@if [ -x "tests/functional/test_deprecation_warnings.sh" ]; then \
		echo "Running deprecation warning tests (TASK-070)..."; \
		cd $(shell pwd) && bash tests/functional/test_deprecation_warnings.sh; \
	else \
		echo "Deprecation warning test script not found or not executable"; \
	fi

package-prep-deb:
	@echo "Preparing Debian package tree..."
	mkdir -p build/debian/$(PROJECT_NAME)-$(VERSION)
	# Copy project sources (excluding build dir)
	rsync -a --exclude build ./ build/debian/$(PROJECT_NAME)-$(VERSION)/
	# Overlay debian packaging metadata
	rm -rf build/debian/$(PROJECT_NAME)-$(VERSION)/debian
	cp -r packaging/deb/debian build/debian/$(PROJECT_NAME)-$(VERSION)/
	# Update changelog version to match VERSION file
	sed -i "1s/^$(PROJECT_NAME) (.*)/$(PROJECT_NAME) ($(VERSION)-1)/" build/debian/$(PROJECT_NAME)-$(VERSION)/debian/changelog || true
	@echo "Debian package tree prepared at build/debian/$(PROJECT_NAME)-$(VERSION)"

package-prep-rpm:
	@echo "Preparing RPM package tree..."
	mkdir -p build/rpm/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	# Create source tarball
	tar czf build/rpm/SOURCES/$(PROJECT_NAME)-$(VERSION).tar.gz --exclude=build .
	# Generate spec from template with current VERSION
	sed -e "s/^Version:.*/Version:        $(VERSION)/" \
	    -e "/^\* /c\* $$(date +'%a %b %d %Y') Bananapeel Team <admin@example.com> - $(VERSION)-1" \
	    packaging/rpm/$(PROJECT_NAME).spec.template > build/rpm/SPECS/$(PROJECT_NAME).spec
	@echo "RPM package tree prepared with:"
	@echo "  - Source tarball: build/rpm/SOURCES/$(PROJECT_NAME)-$(VERSION).tar.gz"
	@echo "  - Spec file: build/rpm/SPECS/$(PROJECT_NAME).spec"

package-deb: package-prep-deb
	@echo "Building Debian package..."
	cd build/debian/$(PROJECT_NAME)-$(VERSION) && dpkg-buildpackage -b -us -uc

package-rpm: package-prep-rpm
	@echo "Building RPM package..."
	rpmbuild -bb --define "_topdir $(PWD)/build/rpm" build/rpm/SPECS/$(PROJECT_NAME).spec

package-freebsd:
	@echo "Building FreeBSD package..."
	mkdir -p build/freebsd
	# FreeBSD package building would go here
	@echo "FreeBSD packaging not yet implemented"

package-all: package-deb package-rpm package-freebsd

help:
	@echo "Available targets:"
	@echo "  all          - Prepare for installation (default)"
	@echo "  install      - Install the tools system-wide"
	@echo "  uninstall    - Remove the installed tools"
	@echo "  clean        - Clean build artifacts"
	@echo "  test         - Run test suite"
	@echo "  package-prep-deb - Prepare Debian package tree"
	@echo "  package-prep-rpm - Prepare RPM package tree"
	@echo "  package-deb  - Build Debian package"
	@echo "  package-rpm  - Build RPM package"
	@echo "  package-freebsd - Build FreeBSD package"
	@echo "  package-all  - Build all package types"
