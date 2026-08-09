# Parses every GDScript file with the real Godot parser and reports only the
# errors that are genuine in isolation.
#
# `godot --check-only --script <file>` loads a single script with no autoloads
# registered, so "Compile Error: Identifier not found: <AutoloadName>" is an
# artifact of the check, not a bug. Parse errors, on the other hand, happen
# before any of that and are always real.
#
# Usage:
#   powershell -File tools/godot_check.ps1 -Godot "C:\path\to\Godot_v4.3-stable_win64.exe"

param(
    [string]$Godot = '',
    [string]$Project = (Split-Path -Parent $PSScriptRoot)
)

# Ordem de busca: -Godot, GODOT_BIN, e o local padrão onde o editor foi
# instalado. Sem isso era preciso passar o caminho em toda chamada.
if (-not $Godot) { $Godot = $env:GODOT_BIN }
if (-not $Godot -or -not (Test-Path $Godot)) {
    $padrao = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.3-stable_win64.exe'
    if (Test-Path $padrao) { $Godot = $padrao }
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Host "Godot nao encontrado. Passe -Godot <caminho do exe> ou defina GODOT_BIN." -ForegroundColor Red
    exit 2
}

# Lido da seção [autoload] do project.godot, e não escrito a mão: uma lista fixa
# aqui envelhece calada e faz um autoload novo aparecer como erro real.
$autoloads = @()
$dentroDaSecao = $false
foreach ($linha in Get-Content (Join-Path $Project 'project.godot')) {
    if ($linha -match '^\[(.+)\]') { $dentroDaSecao = ($Matches[1] -eq 'autoload'); continue }
    if ($dentroDaSecao -and $linha -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') { $autoloads += $Matches[1] }
}
if ($autoloads.Count -eq 0) {
    Write-Host "Nenhum autoload lido de project.godot - o filtro de falso-positivo esta desligado." -ForegroundColor Yellow
    $autoloadPattern = 'Identifier not found: \x00nunca\x00'
} else {
    $autoloadPattern = 'Identifier not found: (' + ($autoloads -join '|') + ')\s*$'
}

# Uma passada do editor em headless para regravar o cache de classes globais.
# Sem isso, um script criado depois da última abertura do editor aparece como
# "Could not find type X" mesmo estando correto.
Write-Host "Reindexando classes..." -ForegroundColor DarkGray
& $Godot --headless --path $Project --editor --quit 2>&1 | Out-Null

$failed = 0
$checked = 0

Get-ChildItem "$Project\scripts" -Recurse -Filter *.gd | ForEach-Object {
    $checked++
    $rel = 'res://' + $_.FullName.Replace("$Project\", '').Replace('\', '/')
    $output = & $Godot --headless --path $Project --check-only --script $rel 2>&1 | Out-String

    $real = $output -split "`n" | Where-Object {
        ($_ -match 'Parse Error|Compile Error') -and
        ($_ -notmatch $autoloadPattern) -and
        # A bare "Compile Error:" with no message is the cascade from a
        # dependency that failed for the autoload reason above.
        ($_ -notmatch 'Compile Error:\s*$')
    }
    if ($real) {
        $failed++
        Write-Host "=== $rel" -ForegroundColor Yellow
        $real | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Red }
    }
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "OK    $checked script(s) parsed clean" -ForegroundColor Green
    exit 0
}
Write-Host "FAIL  $failed of $checked script(s) have real errors" -ForegroundColor Red
exit 1
