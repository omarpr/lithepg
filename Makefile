# LithePG developer entry points.
#
#   make build    — debug build of every target
#   make test     — Swift test suites (live Postgres, TLS, SSH and Neon tests skip
#                   unless their environment variables are set)
#   make run      — build the debug app bundle and open it
#   make app      — release app bundle → dist/LithePG.app, then verify it
#   make verify   — re-run the package checks on dist/LithePG.app
#   make install  — build, verify and replace /Applications/LithePG.app
#   make release  — signed, notarized release: GitHub Release + Homebrew tap
#                   (runs ./script/release_local.sh, which asks for confirmation)
#   make web-test — build and check the promotional website
#   make web-deploy — deploy the website to Fly.io

APP := dist/LithePG.app
RELEASE_LOCAL := ./script/release_local.sh

.PHONY: build test run app verify install release web-test web-deploy

build:
	swift build

test:
	swift test

run:
	./script/build_and_run.sh run

app:
	./script/build_and_run.sh --package

verify:
	./script/package_verify.sh $(APP)

install:
	./script/rebuild_and_install.sh

# release_local.sh is ignored by Git because it holds this Mac's signing settings, so a
# fresh clone does not have it. Say so plainly instead of failing with "No such file".
release:
	@test -x $(RELEASE_LOCAL) || { \
		echo "make release: $(RELEASE_LOCAL) is missing or not executable."; \
		echo "It is a local, Git-ignored wrapper. See docs/RELEASING.md to set it up."; \
		exit 1; \
	}
	$(RELEASE_LOCAL)

web-test:
	cd webapp && bash test.sh

web-deploy:
	cd webapp && npm run deploy
