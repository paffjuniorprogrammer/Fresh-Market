@echo off
REM Auto-fix Firebase CMake for Windows build
if exist "build\windows\x64\extracted\firebase_cpp_sdk_windows\CMakeLists.txt" (
  powershell -Command "(Get-Content 'build/windows/x64/extracted/firebase_cpp_sdk_windows/CMakeLists.txt') -replace 'cmake_minimum_required\\(VERSION 3\\.1\\)', 'cmake_minimum_required(VERSION 3.22)' | Set-Content 'build/windows/x64/extracted/firebase_cpp_sdk_windows/CMakeLists.txt'"
  echo CMakeLists.txt patched!
)
flutter build windows --release

