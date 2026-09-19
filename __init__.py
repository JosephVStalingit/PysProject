"""PysProject package init.

Exposes the canonical version string used by:
    - pyproject.toml
    - Dockerfile LABEL org.opencontainers.image.version
    - CI workflow (auto-tagged releases)
    - `pysproject --version` (after `pip install -e .`)
"""
from __future__ import annotations

from .__version__ import __version__

__all__ = ["__version__"]