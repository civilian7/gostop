# Gostop FMX 앱 빌드 스크립트 (Win64)
# 사용: powershell -ExecutionPolicy Bypass -File build.ps1
# 구조: src\(프로그램) + src\engine\(유닛) → bin\Gostop.exe, assets → bin\assets 동기화
$ErrorActionPreference = 'Stop'

$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$Cgrc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\cgrc.exe'
$Lib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release'
$Root = $PSScriptRoot

New-Item -ItemType Directory -Force "$Root\bin" | Out-Null
New-Item -ItemType Directory -Force "$Root\src\dcu" | Out-Null

# 1) 매니페스트+아이콘 → .res (PerMonitorV2 High-DPI, 고도리 아이콘)
Set-Location "$Root\src"
& $Cgrc 'Gostop.rc' '-foGostop.res'
if ($LASTEXITCODE -ne 0) { throw 'cgrc 실패' }

# 2) FMX 앱 컴파일 → bin\Gostop.exe (dcu는 src\dcu)
$NS = 'System;System.Win;Winapi;System.Types;FMX;Data;Xml'
& $Dcc "-NS$NS" "-U$Lib" "-E$Root\bin" "-NU$Root\src\dcu" 'Gostop.dpr'
if ($LASTEXITCODE -ne 0) { throw 'dcc64 실패' }
Set-Location $Root

# 3) 실행 리소스 동기화: assets → bin\assets (변경·삭제 반영, 리소스 수정 시 빌드로 반드시 복사)
robocopy "$Root\assets" "$Root\bin\assets" /MIR /NJH /NJS /NDL /NFL /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'assets 복사(robocopy) 실패' }
$global:LASTEXITCODE = 0

Write-Host ''
Write-Host '빌드 완료: bin\Gostop.exe (+ bin\assets 동기화)' -ForegroundColor Green
