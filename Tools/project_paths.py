"""Where the tools look for the things that are deliberately not in the repository.

The credentials, the MSAL token cache and the browser profiles live in the project root
*above* the repository, so moving these scripts into version control did not bring any of
them with it. Resolve those paths from PROJECT_ROOT rather than relative to this folder.
"""
import os

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
PROJECT_ROOT = os.path.dirname(REPO)
