# copilot-prompts/

Prompt files do Copilot (`agent: 'agent'`), um por onda do
`RUNBOOK.md`. Autocontidos — não dependem do `RUNBOOK.md` estar
fisicamente no repositório do serviço, só do `AGENTS.md` (já
sincronizado pelo `sync-agents.ps1`).

## Como usar

1. Copie esta pasta inteira para `.github/prompts/` na raiz do
   repositório do serviço (o `sync-agents.ps1` já faz isso
   automaticamente).
2. No Copilot Chat (VS Code, modo Agent), digite `/` — o menu mostra
   todos os prompts disponíveis pelo nome do arquivo.
3. Selecione o da onda que quer rodar. Não precisa digitar mais nada.

## Ordem recomendada

```
/00-scanner-diagnostico      -- rode primeiro, sempre
/01-golden-files
/02-testcontainers
/03-cobertura-unitaria       -- semaforo 90/95, testa logica de negocio pura

/04-e2e-fluxo-critico        -- OPT-IN, nao recomendado pelo scanner.
                                 O proprio prompt exige justificativa
                                 antes de escrever qualquer codigo.
```

O scanner (`00`) recomenda qual das duas ondas falta, com base no que
já existe no serviço — nem todo serviço precisa das duas (um serviço
sem banco de dados, por exemplo, não precisa de Testcontainers).

**Se este serviço também está passando por modernização de versão**
(via `java-modernization-kit`, repositório separado): as ondas de
versão vivem naquele kit, com seu próprio scanner e prompts. Os dois
scanners coletam parte dos mesmos fatos brutos (versão de Java/Boot),
de propósito — cada kit decide algo diferente com eles.

## Nota sobre a feature

Prompt files do Copilot estão em preview público — sintaxe/comportamento
podem mudar. Se `/nome` não aparecer no menu do chat, confirme:
- Está em modo **Agent** (não Ask/Edit)
- A pasta está em `.github/prompts/`, não em outro lugar
- A extensão do Copilot está atualizada

**Confirmado na prática (piloto):** funciona no plugin JetBrains com
versão recente do Copilot (`Settings > Tools > GitHub Copilot >
Customizations > Prompts` mostra `.github/prompts` como localização
reconhecida). **Se não aparecer no seu ambiente:** relatos anteriores
(`microsoft/copilot-intellij-feedback#913`, `#1163`,
`youtrack.jetbrains.com/PY-85160`) indicam que suporte a isso só foi
adicionado a partir da versão 1.5.54 do plugin — atualize o Copilot
antes de investigar mais fundo. Também confirme se sua conta/organização
tem `editor_preview_features` habilitado nessa mesma tela de
Customizations.

**Cuidado comum: confundir com outro painel de chat de IA instalado**
(ex: Claude Code) — os ícones na barra lateral do IntelliJ ficam
próximos e parecidos. Confirme pelo texto no topo do painel ("GitHub
Copilot") antes de assumir que o recurso não funciona.

## Cada prompt segue a mesma disciplina do AGENTS.md

Baseline antes, oráculo é o build real (nunca `--rerun`, use `clean`),
para antes de commitar, nunca edita golden file para passar. Se algo
no comportamento do agente contradisser isso, é a instrução que está
errada, não a regra — reporte para corrigir o prompt file, não ignore
a regra manualmente.

## Pendências conhecidas (backlog, não bloqueante)

- **`00-scanner-diagnostico`: nome de arquétipo às vezes vem com sufixo
  estranho** (ex: `mvc-jpa-multi-datasource-kafka-ready` num serviço
  que comprovadamente não tem Kafka). Achado no teste real contra o
  `ecommerce` — não afetou nenhuma decisão prática do relatório (a
  checklist de próximo passo saiu correta), mas o nome do arquétipo
  ficou impreciso. Suspeita: o agente puxa esse sufixo de algum
  exemplo citado no próprio prompt (`webflux-kafka` aparece como
  exemplo de nome de arquétipo no passo 2) sem intenção real. Ajustar
  o prompt para não sugerir nomes de arquétipo com integrações
  específicas como exemplo, ou pedir explicitamente para o nome
  refletir só o que foi confirmado presente.
