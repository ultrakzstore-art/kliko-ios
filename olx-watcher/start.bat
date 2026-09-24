@echo off
rem Запуск бота на Windows двойным щелчком. Первый раз ставит зависимости.
cd /d "%~dp0"
if not exist node_modules call npm install
if not exist .env (
  copy .env.example .env >nul
  echo Впишите BOT_TOKEN в файл .env и запустите снова.
  notepad .env
  exit /b
)
npm start
pause
