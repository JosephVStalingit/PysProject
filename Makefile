# =============================================================================
#  Makefile  --  cross-platform build commands
#
#  Targets:
#    make help          - show this help
#    make test          - run pytest (unit tests, no FEM)
#    make pipeline      - run full 4-step FEM pipeline
#    make clean         - remove build artifacts
#    make docker-build  - build Docker image
#    make docker-run    - run Docker container
#    make lock          - regenerate requirements.lock from pyproject.toml
#    make wheel         - build Python wheel + sdist
#    make install       - pip install -e . (editable install)
#    make version       - print current version
#    make release       - bump version (usage: make release V=2.3.0)
# =============================================================================

PY         ?= python3
PIP        ?= $(PY) -m pip
VERSION    := $(shell $(PY) -c "import sys; sys.path.insert(0,'.'); import __version__; print(__version__.__version__)")
SHELL      := /bin/bash

.PHONY: help test pipeline clean docker-build docker-run lock wheel install version release lint

help:
	@echo "PysProject v$(VERSION) -- Makefile targets"
	@echo
	@echo "  make test           Run pytest (unit tests, mesh + render)"
	@echo "  make pipeline       Run full 4-step FEM pipeline (gmsh -> ElmerSolver)"
	@echo "  make clean          Remove build artifacts (model3d.msh, mesh/, results/)"
	@echo "  make docker-build   Build Docker image"
	@echo "  make docker-run     Run Docker container"
	@echo "  make lock           Regenerate requirements.lock"
	@echo "  make wheel          Build Python wheel + sdist"
	@echo "  make install        pip install -e . (editable)"
	@echo "  make lint           Run ruff + mypy"
	@echo "  make version        Print current version"
	@echo "  make release V=X.Y.Z Bump version"

test:
	$(PY) -m pytest tests/ -v --tb=short

pipeline:
ifeq ($(OS),Windows_NT)
	.\run_tests.ps1
else
	./run_tests.sh
endif

clean:
ifeq ($(OS),Windows_NT)
	.\clean.ps1
else
	./clean.sh
endif

docker-build:
	docker compose build

docker-run:
	docker compose run --rm fem

lock:
	$(PIP) install pip-tools
	$(PY) -m piptools compile pyproject.toml \
		--output-file=requirements.lock --upgrade --extra dev

wheel:
	$(PIP) install build
	$(PY) -m build --sdist --wheel
	@echo "Built dist/pysproject-$(VERSION)*"

install:
	$(PIP) install -e ".[dev]"

lint:
	ruff check solenoid3d.py tests/ __version__.py
	$(PY) -m mypy solenoid3d.py || true

version:
	@echo "PysProject v$(VERSION)"

# Bump version:  make release V=2.3.0
release:
ifndef V
	$(error Usage: make release V=X.Y.Z)
endif
	@echo "Bumping to v$(V)"
ifeq ($(OS),Windows_NT)
	$(PY) -c "import io; p=r'__version__.py'; s=open(p,encoding='utf-8').read(); import re; s=re.sub(r'\"[0-9]+\.[0-9]+\.[0-9]+\"','\"$(V)\"',s); open(p,'w',encoding='utf-8').write(s)"
else
	sed -i.bak -E 's/"[0-9]+\.[0-9]+\.[0-9]+"/"$(V)"/' __version__.py && rm -f __version__.py.bak
endif
	$(PY) -c "import re; s=open('pyproject.toml',encoding='utf-8').read(); s=re.sub(r'(version\s*=\s*)\"[0-9]+\.[0-9]+\.[0-9]+\"', r'\\1\"$(V)\"', s); open('pyproject.toml','w',encoding='utf-8').write(s)"
	@echo "Done.  Don't forget to commit and tag:"
	@echo "  git add __version__.py pyproject.toml CHANGELOG.md"
	@echo "  git commit -m 'release: v$(V)'"
	@echo "  git tag v$(V)"