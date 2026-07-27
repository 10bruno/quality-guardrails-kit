# quality-guardrails-kit

Golden files, Testcontainers, mutation testing e o linter de escopo de
diff — a rede de segurança que qualquer serviço pode adotar, com ou
sem upgrade de versão acontecendo junto.

Extraído do piloto `ecommerce` (parte do programa original de
modernização Java 25 LTS + Spring Boot 4.1) e desacoplado dele em
24/07/2026, porque a necessidade de mais garantia de teste é
frequentemente independente da necessidade de subir versão.

---

## Quando usar este kit

- **Serviço já na última versão**, ou sem necessidade de modernização,
  mas que precisa de mais garantia de qualidade de teste.
- **Serviço que vai passar por modernização de versão** — use este kit
  junto com o `java-modernization-kit` (repositório separado). Aquele
  kit referencia este aqui como pré-requisito da Onda 2, e checkpoint
  depois das Ondas 3 e 4.

Este kit nunca depende do `java-modernization-kit` — a relação é
sempre numa direção só.

---

## Passo 0 — configuração inicial (uma vez por máquina) + sincronização (toda vez)

Duas coisas diferentes: **clonar o kit** (uma vez, nesta máquina) e
**sincronizar um serviço específico** (toda vez que for trabalhar
nele). O script NUNCA clona nem atualiza o kit sozinho — isso é
manual, de propósito (autenticação Git varia por máquina, tentar
automatizar isso se mostrou frágil na prática).

### 1. Clone — uma vez, nesta máquina, do jeito que você já clona qualquer repositório

```powershell
git clone https://SEU-GITLAB/quality-guardrails-kit.git "$env:USERPROFILE\quality-guardrails-kit"
```

### 2. Você já tem (ou vai ter) o repositório do SERVIÇO clonado em algum lugar — separado do kit

### 3. Sincronize

```powershell
cd F:\dev\meu-servico

& "$env:USERPROFILE\quality-guardrails-kit\scripts\sync-agents.ps1"
```

Copia `AGENTS.md`, `.github/copilot-instructions.md`, os prompt files
e os guardrails (`scripts/diff_scope_linter.py` +
`context/guardrails/scope-rules.json`) para dentro do repositório do
serviço.

**Não commita sozinho.** Revisar o diff e decidir commitar é sempre
manual.

Detalhes completos: `scripts/sync-agents.ps1` e `RUNBOOK.md`.

---

## Estrutura

```
AGENTS.md                         regras invioláveis, standalone
RUNBOOK.md                        ondas de golden files/Testcontainers + Anexo B (guardrails de automação)
context/
  achados/                        achados de teste/infra, agnósticos de versão
  guardrails/                     scope-rules.json, linter, snippets de PIT
  servicos/                       fichas de diagnóstico
copilot-prompts/
  00-scanner-diagnostico.prompt.md
  01-golden-files.prompt.md
  02-testcontainers.prompt.md
scripts/
  diff_scope_linter.py            testado com casos reais
  sync-agents.ps1
```

---

## Achados reutilizáveis

- **Golden file: sempre round-trip, nunca só serialização** — o achado
  mais severo do piloto original (bug real do Jackson 3) só aparecia
  na desserialização.
- **`ddl-auto=create-drop` + Testcontainers gera race condition no
  shutdown.** Sempre `create`.
- **Linter de escopo de diff, testado**: 4+ cenários reais confirmados,
  incluindo o caso de borda de instalar o próprio guardrail (ver
  `context/guardrails/scope-rules.json`, campo `sempre_permitido`).
- **PIT (mutation testing) tem limitação real e documentada com Java
  25 + Gradle 8.x** — ver `RUNBOOK.md`, Anexo B1, achado completo com
  as issues reais que confirmam.
