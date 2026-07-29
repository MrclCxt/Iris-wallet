# Gera os instaladores e publica uma release no GitHub.
#
#   .\publicar_release.ps1 -Versao v0.1.0
#
# O repositório é PRIVADO: os links exigem login no GitHub com acesso a ele.
# Isso é proposital — é uma carteira em desenvolvimento, na testnet4.

param(
    [Parameter(Mandatory = $true)][string]$Versao,
    [string]$Notas = "",
    [switch]$PularBuild
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$saida = Join-Path $PSScriptRoot "build\release"
New-Item -ItemType Directory -Force $saida | Out-Null

if (-not $PularBuild) {
    # O APK universal traz arm64, arm 32-bit e x86_64 — instala em qualquer
    # aparelho. Demora porque o Rust é recompilado em release por arquitetura.
    Write-Host "==> APK universal (demorado: Rust em release por arquitetura)"
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "build do APK falhou" }

    # O cargokit pode falhar em compilar o Rust e o Gradle segue empacotando a
    # .so anterior, saindo com exit 0. Já aconteceu neste projeto e passou
    # semanas despercebido: verificar é obrigatório, não zelo extra.
    Write-Host "==> Windows"
    $log = Join-Path $env:TEMP "iris_win_build.log"
    flutter build windows --release 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        if (Select-String -Path $log -Pattern "LNK1104" -Quiet) {
            throw "LNK1104: feche o Iris Wallet no PC — ele segura o iris_wallet.exe"
        }
        throw "build do Windows falhou"
    }
    if (Select-String -Path $log -Pattern "SEVERE" -Quiet) {
        throw "cargokit reportou SEVERE: o Rust não compilou e a .so/.dll antiga seria empacotada"
    }
}

$apkOrigem = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkOrigem)) { throw "APK não encontrado em $apkOrigem" }
$apk = Join-Path $saida "iris-wallet-$Versao.apk"
Copy-Item $apkOrigem $apk -Force

# O .exe sozinho não roda: precisa das DLLs do Flutter, das bibliotecas Rust
# (ldk_node/lwk) e da pasta data. Vai a pasta inteira, compactada.
$winDir = "build\windows\x64\runner\Release"
if (-not (Test-Path "$winDir\iris_wallet.exe")) { throw "executável não encontrado em $winDir" }
$zip = Join-Path $saida "iris-wallet-$Versao-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$winDir\*" -DestinationPath $zip

Write-Host ""
Write-Host "Artefatos:"
Get-Item $apk, $zip | ForEach-Object {
    "{0,-42} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB)
}

$corpo = if ($Notas) { $Notas } else {
@"
Build de teste da Iris Wallet — rede **testnet4**. Não use com bitcoin real.

| Arquivo | Para |
|---|---|
| ``iris-wallet-$Versao.apk`` | Android (universal: arm64, arm 32-bit e x86_64) |
| ``iris-wallet-$Versao-windows.zip`` | Windows 10/11 — extraia a pasta inteira e rode ``iris_wallet.exe`` |

**Android:** é instalação fora da loja, então o aparelho vai pedir para permitir
"instalar apps desconhecidos" para o navegador ou gerenciador de arquivos usado.

**Windows:** o SmartScreen deve avisar que o app não é reconhecido — em "Mais
informações" há a opção de executar assim mesmo. O executável não roda sozinho:
mantenha os arquivos junto da pasta ``data``.

Commit: $(git rev-parse --short HEAD)
"@
}

Write-Host ""
Write-Host "==> Publicando release $Versao"
gh release create $Versao $apk $zip --title "Iris Wallet $Versao" --notes $corpo
if ($LASTEXITCODE -ne 0) { throw "gh release create falhou" }

gh release view $Versao --json url --jq .url
