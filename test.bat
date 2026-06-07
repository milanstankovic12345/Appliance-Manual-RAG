@echo off  
set " "URL=https://google.com  
for /L %%I in (1,1,3) do ( curl -fsS -m 2 -o nul %%URL%% >nul 2>&1 & if not errorlevel 1 echo OK )  
