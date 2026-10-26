#!/usr/bin/env python3
"""Compatibility entry point: regenerate resources from the canonical catalog."""
from sync_localizations import sync

if __name__ == "__main__":
    sync()
