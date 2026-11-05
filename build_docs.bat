@echo off
echo ========================================================
echo   Building Static Production Documentation Site...
echo ========================================================
echo.
.\.venv\Scripts\mkdocs.exe build
echo.
echo Build complete! Static site generated in folder: \site
pause

