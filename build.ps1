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

# 3) 실행 리소스 동기화: 런타임에 필요한 것만 복사(png·wav). svg·ogg·문서(md/tsv)는 제외
#    - 카드/아바타 png, 효과음 wav 만 런타임에 로드됨(svg는 png 원본, ogg는 미사용)
robocopy "$Root\assets" "$Root\bin\assets" /MIR /XD "$Root\assets\hwatu\svg" /XF *.ogg *.svg *.md *.tsv /NJH /NJS /NDL /NFL /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'assets 복사(robocopy) 실패' }
$global:LASTEXITCODE = 0

# robocopy /XF·/XD 는 제외 파일을 삭제하지 않으므로, 기존 배포분에 남은 불필요 파일/폴더 정리
Get-ChildItem -Path "$Root\bin\assets" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -in '.ogg', '.svg', '.md', '.tsv' } |
  Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "$Root\bin\assets" -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -eq 'svg' } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '빌드 완료: bin\Gostop.exe (+ bin\assets 동기화)' -ForegroundColor Green
