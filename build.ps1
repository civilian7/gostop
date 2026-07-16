# Gostop FMX 앱 빌드 스크립트 (Win64)
# 사용: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'

$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$Cgrc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\cgrc.exe'
$Lib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release'
$Root = $PSScriptRoot

Set-Location $Root

# 1) 매니페스트 → .res (PerMonitorV2 High-DPI)
& $Cgrc 'Gostop.rc' '-foGostop.res'
if ($LASTEXITCODE -ne 0) { throw 'cgrc 실패' }

# 2) FMX 앱 컴파일
$NS = 'System;System.Win;Winapi;System.Types;FMX;Data;Xml'
& $Dcc "-NS$NS" "-U$Lib" '-E.' '-N0.' 'Gostop.dpr'
if ($LASTEXITCODE -ne 0) { throw 'dcc64 실패' }

# 3) 중간 산출물 정리
Remove-Item -Path '*.dcu' -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '빌드 완료: Gostop.exe' -ForegroundColor Green
