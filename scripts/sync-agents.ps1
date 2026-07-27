<#
.SYNOPSIS
    Sincroniza AGENTS.md, .github/copilot-instructions.md,
    .github/prompts/*.prompt.md e os guardrails do quality-guardrails-kit
    (ja clonado localmente por voce) para o repositorio do servico atual.

.DESCRIPTION
    Passo 0 de qualquer onda (ver RUNBOOK.md). Nao commita nada --
    so copia os arquivos e mostra o diff. Revisao e commit continuam
    manuais, por design (regra 15 do AGENTS.md: nunca commit/push/merge
    sem confirmacao humana).

    Roda a partir da RAIZ do repositorio do servico (nao do kit).

    IMPORTANTE -- este script NAO clona nem atualiza o quality-guardrails-kit
    sozinho. Ele assume que voce ja tem o kit clonado localmente, usando
    a autenticacao Git que ja funciona normalmente na sua maquina (HTTPS,
    SSH com chave OpenSSH, ou SSH com .ppk/PuTTY -- o que for). Isso e
    proposital: tentar automatizar clone/pull dentro do script se
    mostrou fragil na pratica, porque cada maquina pode ter configuracao
    de autenticacao diferente (achado real de uso, ver RUNBOOK.md).

    Se voce ainda nao tem o kit clonado, ou se quer a versao mais
    recente dele, faca isso VOCE MESMO, manualmente, antes de rodar
    este script:
        cd para onde quiser guardar o kit
        git clone <url-do-repo-do-kit>
        (ou, se ja clonado: cd para la, git pull)

.PARAMETER KitCachePath
    Caminho onde o quality-guardrails-kit ja foi clonado localmente por voce.
    Default: %USERPROFILE%\quality-guardrails-kit (local recomendado no
    README.md, Passo 0). Se voce clonou em outro lugar, informe aqui.

.EXAMPLE
    # Kit clonado no local padrao recomendado (README.md, Passo 0):
    .\sync-agents.ps1

.EXAMPLE
    # Kit clonado em outro lugar:
    .\sync-agents.ps1 -KitCachePath "C:\onde-voce-clonou\quality-guardrails-kit"
#>

param(
    [string]$KitCachePath
)

$ErrorActionPreference = "Stop"

# --- Resolve onde o kit foi clonado (nao clona nada aqui) ----------------

if (-not $KitCachePath) {
    $KitCachePath = Join-Path $env:USERPROFILE "quality-guardrails-kit"
}

Write-Host "Procurando o kit em: $KitCachePath" -ForegroundColor Cyan

$sourceAgents = Join-Path $KitCachePath "AGENTS.md"

if (-not (Test-Path $KitCachePath)) {
    Write-Error @"
Kit nao encontrado em '$KitCachePath'.

Este script NAO clona o kit sozinho -- clone manualmente primeiro,
usando a autenticacao Git que ja funciona na sua maquina:

    git clone <url-do-repo-do-kit> "$KitCachePath"

(ou clone em outro lugar e rode este script de novo com
-KitCachePath "seu\caminho\aqui")

Ver README.md do kit, secao "Passo 0", para o comando completo.
"@
    exit 1
}

if (-not (Test-Path $sourceAgents)) {
    Write-Error "Encontrei a pasta '$KitCachePath', mas AGENTS.md nao esta la. Confirme se o clone terminou direito, ou se e mesmo a pasta do quality-guardrails-kit (nao uma pasta vazia ou de outro projeto)."
    exit 1
}

Write-Host "Kit encontrado. Usando como esta -- este script nao atualiza o kit automaticamente." -ForegroundColor Green
Write-Host "(Se quiser a versao mais recente do kit: cd '$KitCachePath', depois 'git pull', manualmente, antes de rodar este script de novo.)" -ForegroundColor DarkGray
Write-Host ""

# --- Confirma que estamos na raiz de um repo de servico (nao do kit) ---

if (-not (Test-Path ".git")) {
    Write-Error "Este diretorio nao parece ser a raiz de um repositorio git. Rode este script a partir da raiz do repo do SERVICO, nao do kit."
    exit 1
}

$currentRepoPath = (Get-Location).Path
if ($currentRepoPath -eq $KitCachePath) {
    Write-Error "Voce esta dentro do proprio repositorio do kit. Rode este script de dentro do repositorio do SERVICO que voce quer atualizar."
    exit 1
}

# --- Compara antes de sobrescrever, para mostrar o que vai mudar -------

$destAgents = ".\AGENTS.md"
$destCopilotDir = ".\.github"
$destCopilot = Join-Path $destCopilotDir "copilot-instructions.md"

$agentsExistiaAntes = Test-Path $destAgents
$copilotExistiaAntes = Test-Path $destCopilot

if ($agentsExistiaAntes) {
    $diffCount = (Compare-Object (Get-Content $destAgents) (Get-Content $sourceAgents)).Count
    if ($diffCount -eq 0) {
        Write-Host "AGENTS.md ja esta identico ao do kit. Nada a fazer aqui." -ForegroundColor Green
    } else {
        Write-Host "AGENTS.md local difere do kit em $diffCount linha(s). Atualizando." -ForegroundColor Yellow
    }
} else {
    Write-Host "AGENTS.md nao existe neste repo ainda. Criando." -ForegroundColor Yellow
}

# --- Copia os dois arquivos ----------------------------------------------

Copy-Item -Path $sourceAgents -Destination $destAgents -Force

if (-not (Test-Path $destCopilotDir)) {
    New-Item -ItemType Directory -Path $destCopilotDir | Out-Null
}
Copy-Item -Path $sourceAgents -Destination $destCopilot -Force

# --- Sincroniza os prompt files (.github/prompts/) ------------------------

$sourcePromptsDir = Join-Path $KitCachePath "copilot-prompts"
$destPromptsDir = Join-Path $destCopilotDir "prompts"
$promptsSincronizados = 0

if (Test-Path $sourcePromptsDir) {
    if (-not (Test-Path $destPromptsDir)) {
        New-Item -ItemType Directory -Path $destPromptsDir | Out-Null
    }
    Get-ChildItem -Path $sourcePromptsDir -Filter "*.prompt.md" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $destPromptsDir $_.Name) -Force
        $promptsSincronizados++
    }
} else {
    Write-Warning "Pasta 'copilot-prompts' nao encontrada no kit em '$KitCachePath'. Prompt files nao foram sincronizados -- confirme se o kit esta atualizado (git pull manual na pasta do kit) ou se a pasta existe nessa versao."
}

# --- Sincroniza os guardrails (linter de escopo + regras) -----------------
#
# So sincroniza os arquivos diretamente utilizaveis (script + config).
# Os snippets de PIT (pom-pitest-snippet.xml, build-gradle-pitest-snippet.gradle)
# NAO sao copiados automaticamente -- exigem integracao manual dentro do
# pom.xml/build.gradle existente do servico, nao sao arquivo solto para
# so colocar no lugar.

$sourceGuardrailsDir = Join-Path $KitCachePath "context\guardrails"
$sourceKitScriptsDir = Join-Path $KitCachePath "scripts"
$destGuardrailsDir = ".\context\guardrails"
$destScriptsDir = ".\scripts"
$guardrailsSincronizados = 0

if (Test-Path $sourceGuardrailsDir) {
    if (-not (Test-Path $destGuardrailsDir)) {
        New-Item -ItemType Directory -Path $destGuardrailsDir -Force | Out-Null
    }
    if (-not (Test-Path $destScriptsDir)) {
        New-Item -ItemType Directory -Path $destScriptsDir -Force | Out-Null
    }

    $sourceScopeRules = Join-Path $sourceGuardrailsDir "scope-rules.json"
    if (Test-Path $sourceScopeRules) {
        Copy-Item -Path $sourceScopeRules -Destination (Join-Path $destGuardrailsDir "scope-rules.json") -Force
        $guardrailsSincronizados++
    }

    # Sincroniza TODOS os scripts .py da pasta scripts/ do kit -- generico
    # de proposito, para nao depender de lembrar de listar cada arquivo
    # novo aqui (foi exatamente isso que quebrou antes: coverage_gate.py
    # foi adicionado ao kit e esquecido nesta lista, ficando sem
    # sincronizar em servicos ja sincronizados anteriormente).
    if (Test-Path $sourceKitScriptsDir) {
        Get-ChildItem -Path $sourceKitScriptsDir -Filter "*.py" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $destScriptsDir $_.Name) -Force
            $guardrailsSincronizados++
        }
    }
} else {
    Write-Warning "Pasta 'context/guardrails' nao encontrada no kit em '$KitCachePath'. Guardrails nao foram sincronizados -- confirme se o kit esta atualizado."
}

Write-Host ""
Write-Host "Sincronizado:" -ForegroundColor Green
Write-Host "  AGENTS.md                            $(if ($agentsExistiaAntes) {'(atualizado)'} else {'(novo)'})"
Write-Host "  .github/copilot-instructions.md       $(if ($copilotExistiaAntes) {'(atualizado)'} else {'(novo)'})"
Write-Host "  .github/prompts/*.prompt.md           ($promptsSincronizados arquivo(s))"
Write-Host "  scripts/*.py + context/guardrails/scope-rules.json ($guardrailsSincronizados arquivo(s))"
Write-Host ""
Write-Host "PROXIMO PASSO (manual, nao automatizado por proposito):" -ForegroundColor Cyan
Write-Host "  git status"
Write-Host "  git diff -- AGENTS.md"
Write-Host "  git add AGENTS.md .github/copilot-instructions.md .github/prompts/ scripts/ context/guardrails/scope-rules.json"
Write-Host "  git commit -m 'docs: sincroniza AGENTS.md, prompt files e guardrails do quality-guardrails-kit'"
Write-Host ""
Write-Host "Revise o diff antes de commitar -- este script nunca commita sozinho." -ForegroundColor Yellow
Write-Host ""
Write-Host "NOTA: os snippets de PIT (pom-pitest-snippet.xml / build-gradle-pitest-snippet.gradle)" -ForegroundColor DarkGray
Write-Host "nao sao sincronizados automaticamente -- exigem integracao manual no pom.xml/build.gradle." -ForegroundColor DarkGray
