# context/guardrails/

Arquivos de apoio ao Anexo E do `RUNBOOK.md` (guardrails para reduzir
dependência de revisão humana por onda).

## `scope-rules.json` + `scripts/diff_scope_linter.py`

O linter de escopo de diff (E2). **Testado de verdade** — 4 cenários
confirmados: mudança dentro do escopo (passa), mudança fora do escopo
(bloqueia), violação de regra `deny` mesmo com `allow` amplo cobrindo
(bloqueia), branch sem onda configurada (passa com aviso, não bloqueia
por omissão).

Uso:
```bash
python3 scripts/diff_scope_linter.py --base main --rules context/guardrails/scope-rules.json
```

Funciona por convenção de nome de branch — a mesma já usada em todo o
`RUNBOOK.md` e nos prompt files (`onda-3-boot-major`, etc). Sem
dependência externa (só biblioteca padrão do Python — decisão
deliberada, para não exigir `pip install` em runner de CI limpo).

**Wire no GitLab CI:** adicione como job separado, antes de qualquer
outro step, no `.gitlab-ci.yml` de cada serviço:
```yaml
lint-escopo-onda:
  stage: validate
  script:
    - python3 scripts/diff_scope_linter.py --base main --rules context/guardrails/scope-rules.json
  rules:
    - if: '$CI_MERGE_REQUEST_ID'
```

Adicione novas ondas ao `scope-rules.json` conforme o programa cria
novos arquétipos — é arquivo de configuração, editar não exige tocar
no script.

## `pom-pitest-snippet.xml` / `build-gradle-pitest-snippet.gradle`

Configuração de mutation testing (E1) para Maven e Gradle
respectivamente. **Não testado por mim** — sem acesso ao Maven
Central/plugin repository no ambiente onde foi escrito. Copie o
conteúdo relevante para o `pom.xml`/`build.gradle` do serviço, rode
manualmente uma vez (`mvn org.pitest:pitest-maven:mutationCoverage` ou
`./gradlew pitest`) antes de colocar no pipeline — confirme que o
`mutationThreshold` de 70% é razoável para aquele serviço específico
antes de deixá-lo bloquear build automaticamente. Esse número é ponto
de partida, não verdade importada de lugar nenhum.

## Achado real de teste: PIT não é viável em Java 25 + Gradle 8.x hoje (22/07/2026)

Testado contra o `ecommerce` (Java 25, Gradle 8.14.5, plugin
`info.solidsoft.pitest:1.19.0`). Resultado: `0/143 (0%)` de cobertura,
`0 testes examinados` -- todas as mutações reportadas como
`NO_COVERAGE`, mesmo com a suíte inteira passando normalmente fora do
PIT.

**Causa raiz, confirmada em duas issues reais, não suposição:**

1. `szpak/gradle-pitest-plugin#301` e `#338` -- o plugin não respeita
   o toolchain do Gradle. Sempre executa PIT com o JVM que **iniciou o
   processo do Gradle** (o daemon), não o selecionado em
   `java { toolchain { ... } }`. No ambiente testado, o daemon rodava
   sob Java 19 (`JAVA_HOME`/PATH do sistema), enquanto o projeto
   compila para Java 25 -- descompasso total entre o bytecode gerado
   e o JVM que tentou executá-lo.

2. `gradle/gradle#35111` ("Support Java 25 on Gradle 8"), status
   `closed:not-fixed` -- **Gradle 8.x não consegue rodar o próprio
   daemon sob Java 25** (`Unsupported class file major version 69`).
   Suporte de daemon vai até Java 24 (Gradle 8.14 release notes).

**Por que não há workaround simples:** mesmo se o item 1 fosse
contornado manualmente (forçar `org.gradle.java.home` para Java 25),
o item 2 impede isso -- o próprio Gradle 8.x não sobe sob Java 25.
E mesmo se subisse, classes compiladas para Java 25 não carregam em
JVM mais antiga (24 ou abaixo) -- limitação de JVM, não de config.

**Estado real:** dependência de duas correções upstream fora do nosso
controle -- Gradle 9.x (ainda não confirmado se resolve) e uma versão
futura do `gradle-pitest-plugin` que finalmente implemente suporte a
toolchain (pedido em aberto desde 2021).

**Recomendação para o programa:** não bloquear a adoção de mutation
testing por causa disso -- testar primeiro em serviços que ainda não
migraram para Java 25 (LTS anterior, 21 ou inferior), onde a cadeia de
ferramentas é madura. Retestar em serviços Java 25 + Gradle quando
Gradle 9 estiver disponível, ou quando o plugin do PIT publicar
correção para este problema especificamente.

## `coverage_gate.py`

Semáforo de cobertura de linha (90/95), lendo o relatório XML do
JaCoCo. **Testado de verdade** — 4 cenários confirmados: vermelho
(bloqueia), amarelo (passa com aviso), verde (passa limpo), e
confirmação de que lê o contador agregado do relatório, não soma
com os contadores aninhados de pacote/classe por engano.

```bash
python3 scripts/coverage_gate.py --report build/reports/jacoco/test/jacocoTestReport.xml
```

Limiares ajustáveis via `--verde`/`--amarelo` se o padrão 95/90 não
for o combinado para um serviço específico.

## Achado real de teste: sync-agents.ps1 tinha lista de scripts incompleta (25/07/2026)

Rodando `/00-scanner-diagnostico` contra o `ecommerce` de verdade, o
scanner reportou `scripts/coverage_gate.py ausente` — mesmo o serviço
já tendo sido sincronizado antes. Causa: `sync-agents.ps1` copiava
`diff_scope_linter.py` por nome fixo (hardcoded), e `coverage_gate.py`
foi adicionado ao kit depois, sem essa lista ser atualizada junto —
ficou esquecido silenciosamente em qualquer serviço já sincronizado
antes da sua criação.

**Corrigido:** o script agora sincroniza **toda a pasta `scripts/`**
do kit genericamente (`Get-ChildItem -Filter "*.py"`), não mais nome
por nome. Isso elimina a classe inteira de bug — qualquer script novo
adicionado ao kit no futuro sincroniza automaticamente, sem precisar
lembrar de editar `sync-agents.ps1` de novo.

**Se você já tinha sincronizado um serviço antes desta correção**,
rode o sync de novo para pegar `coverage_gate.py` (e qualquer script
futuro) que possa ter ficado para trás.
