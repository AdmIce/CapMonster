# Lança uma versão nova do CapMonster.
#
#   powershell -File tools/lancar.ps1 -Versao 0.2.0 -Notas "Chat e mundo online"
#
# O que ele faz: grava a versão no project.godot, comita, cria a tag e empurra.
# O GitHub Actions (.github/workflows/release.yml) vê a tag, exporta o cliente e
# publica a release com o CapMonster.exe e o CapMonster.pck anexados.
#
# A partir daí, quem estiver com o jogo aberto no menu recebe o aviso de versão
# nova e atualiza sozinho — ninguém precisa mandar arquivo para ninguém.

param(
    [Parameter(Mandatory = $true)][string]$Versao,
    [string]$Notas = ""
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot

if ($Versao -notmatch '^\d+\.\d+\.\d+$') {
    Write-Host "Versao precisa ser no formato N.N.N (ex.: 0.2.0)." -ForegroundColor Red
    exit 1
}

# Trabalho não comitado viraria parte da release sem ninguém revisar.
$sujo = git -C $raiz status --porcelain
if ($sujo) {
    Write-Host "Ha alteracoes nao comitadas:" -ForegroundColor Yellow
    Write-Host $sujo
    Write-Host "Comite ou descarte antes de lancar." -ForegroundColor Red
    exit 1
}

$projeto = Join-Path $raiz "project.godot"
$texto = Get-Content $projeto -Raw
if ($texto -notmatch 'config/version="[^"]*"') {
    Write-Host "Nao achei config/version no project.godot." -ForegroundColor Red
    exit 1
}
$texto = $texto -replace 'config/version="[^"]*"', "config/version=`"$Versao`""
Set-Content -Path $projeto -Value $texto -NoNewline -Encoding utf8

$mensagem = if ($Notas -ne "") { "v${Versao}: $Notas" } else { "v$Versao" }

git -C $raiz add project.godot
git -C $raiz commit -m $mensagem
git -C $raiz tag -a "v$Versao" -m $mensagem
git -C $raiz push origin main
git -C $raiz push origin "v$Versao"

Write-Host ""
Write-Host "Tag v$Versao empurrada." -ForegroundColor Green
Write-Host "O build roda em: https://github.com/AdmIce/CapMonster/actions" -ForegroundColor Gray
Write-Host "A release aparece em: https://github.com/AdmIce/CapMonster/releases" -ForegroundColor Gray
