@echo off
echo ========================================================
echo   Starting Production Backend Documentation Server...
echo ========================================================
echo.
echo Opening browser at http://localhost:8000 ...
start http://localhost:8000
.\.venv\Scripts\mkdocs.exe serve
pause

