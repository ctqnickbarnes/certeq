@echo off
rem Windows launcher: put this folder on PATH (or call it by full path), needs uv (winget install astral-sh.uv)
uv run --script "%~dp0soefix.py" %*
