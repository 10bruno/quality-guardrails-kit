# Runbook — Rede de Segurança (Golden Files + Testcontainers + Guardrails)

> Extraído do piloto `ecommerce` (parte do programa original de
> modernização Java 25 LTS + Spring Boot 4.1). Standalone — serve para
> qualquer serviço que precise de mais garantia de teste, com ou sem
> upgrade de versão acontecendo junto.

---

## Quando usar este kit

> **Convenção:** referências futuras a ferramenta/agente interno da
> empresa (ex: APM já existente, para a onda de performance) seguem o
> mesmo padrão de link-em-texto-sem-clone usado entre este kit e o
> `java-modernization-kit`. Procure por `LINK-EMPRESA` neste
> repositório — sinaliza lacuna deliberada, preenchida quando a
> ferramenta real for confirmada.

- Serviço já está na última versão (ou não tem necessidade de
  modernização), mas precisa de mais garantia de qualidade de teste.
- Serviço vai passar por modernização de versão — neste caso, use
  **junto** com o `java-modernization-kit` (ele referencia este aqui
  como pré-requisito logo após a Onda 0 daquele kit, e checkpoint de
  novo na Onda -1 e depois da Onda 3).

---

## Antes de tudo

1. **Diagnóstico do serviço rodado** (`copilot-prompts/00-scanner-diagnostico.prompt.md`).
   Detecta arquétipo, integrações, e o que já existe de rede de
   segurança — mesmo sem saber nada sobre versão de Java/Boot.
2. **`AGENTS.md` + `.github/copilot-instructions.md` + `.github/prompts/*.prompt.md`
   copiados para a raiz do repositório do serviço.** Use
   `scripts/sync-agents.ps1`. Mesma sincronização recorrente de sempre
   — repita quando retomar trabalho depois de um intervalo.

---

## Tronco comum — toda onda, sem exceção

- **Uma onda = um commit isolado = um PR.**
- **Baseline verde antes de qualquer onda** (`clean build`).
- **`clean build`, nunca `--rerun`** — use `--rerun-tasks` ou `clean`.
- **Golden file quebrou → PARE.** Nunca edite `.json`/`.sql` para
  passar.
- **Nunca commite/push/merge sem confirmação humana.**

---

## Ondas deste kit

| Onda | O quê | Prompt |
|---|---|---|
| Golden files | Contrato de serialização, round-trip obrigatório | `copilot-prompts/01-golden-files.prompt.md` |
| Testcontainers | Persistência real + baseline SQL + guarda N+1 | `copilot-prompts/02-testcontainers.prompt.md` |
| Cobertura unitária | Semáforo 90/95 de linha, valida lógica de negócio pura | `copilot-prompts/03-cobertura-unitaria.prompt.md` |
| **E2E (opcional)** | Fluxo crítico via HTTP real, banco real — **não recomendada pelo scanner**, exige justificativa do engenheiro | `copilot-prompts/04-e2e-fluxo-critico.prompt.md` |

Nenhuma onda aqui exige a outra primeiro — dependem só das integrações
reais que o scanner encontrar (se o serviço não tem banco, a onda de
Testcontainers simplesmente não se aplica).

Explicação de cada técnica, exemplo claro, e onde se encaixa na
pirâmide de testes: `context/piramide-de-testes.md`.

---

## Anexo A — Detalhamento técnico (golden files, testcontainers, SQL, N+1)

### A1. Golden files — sempre round-trip, nunca só serialização

Por que round-trip, não só serialização unidirecional: o achado mais
severo deste piloto (bug real do Jackson 3 na detecção de creator) só
aparecia na desserialização — a serialização continuava byte-idêntica
o tempo todo. Um golden file que só testasse "objeto para JSON" teria
passado, verde, e a falha só apareceria em produção no primeiro POST
real.

```java
@JsonTest
class XGoldenTest {
    @Autowired
    private JacksonTester<X> json;

    @Test
    void serializacao_naoMudou() throws Exception {
        assertThat(json.write(fixture())).isEqualToJson(new ClassPathResource("golden/x.json"));
    }

    @Test
    void roundTrip_preservaTiposEValores() throws Exception {
        var jsonContent = json.write(fixture()).getJson();
        var desserializado = json.parseObject(jsonContent);
        assertThat(desserializado.getCampo()).isEqualByComparingTo(valorEsperado);
        // isEqualByComparingTo para BigDecimal, nao isEqualTo -- escala pode diferir
    }
}
```

Descubra o formato antes de fixar o JSON — nunca chute. Escreva um
teste de descoberta primeiro (imprime o JSON real gerado), confirma o
resultado, só então fixa o arquivo esperado. Usado repetidamente no
piloto para `LocalDate`/`BigDecimal` — o formato real (string ISO,
número sem escala fixa) só se sabe rodando.

### A2. Testcontainers — `ddl-auto=create`, nunca `create-drop`

`create-drop` causa race condition no shutdown do Spring contra o
container já derrubado pelo JUnit — timeouts de 30s por `DataSource`,
sem quebrar o build, mas custando tempo real por execução. Container
inteiro desaparece de qualquer forma; não há razão para o Hibernate
tentar limpar antes.

### A3. Baseline de SQL — não só "passou", captura o SQL real

```java
public class SqlCapturingStatementInspector implements StatementInspector {
    private static final List<String> CAPTURED = Collections.synchronizedList(new ArrayList<>());
    @Override public String inspect(String sql) { CAPTURED.add(sql); return sql; }
    // ... captured(), clear(), countStatementsStartingWith()
}
```

Registrado via `spring.jpa.properties.hibernate.session_factory.statement_inspector`
no `@DynamicPropertySource` — propaga para múltiplos `EntityManagerFactory`
manuais mesmo sem `.properties()` explícito em cada `Config.java`
(confirmado empiricamente no piloto).

Compare contra arquivo versionado, com join fixo em `"\n"` e
normalização `\r\n` para `\n` na leitura — evita que `core.autocrlf`
do Windows quebre a comparação contra CI Linux.

### A4. Guarda de N+1 — contagem exata, não limite superior

`assertThat(count).isEqualTo(N)`, não `<= N` — pega regressão para
mais e para menos (queda de query também é sinal de mudança de
comportamento).

Achado a esperar: entidades com `@Id` atribuído manualmente (sem
`@GeneratedValue`) geram 1 `SELECT` a mais que o esperado — `save()`
chama `merge()`, não `persist()`, porque não há como saber se o
registro é novo sem consultar. Não é bug, é baseline correto.

---


---

## Anexo B — Guardrails para reduzir dependência de revisão humana por onda

> Contexto do problema: o programa não tem QA dedicado para homologar
> onda por onda em N serviços. O objetivo é automação real, mas com
> garantia de que comportamento, requisitos funcionais e não-funcionais
> se mantêm — não "confiar no agente", é "construir mecanismo que prova
> sozinho que está seguro, e reservar humano só para o que realmente
> precisa de julgamento".

Tudo que construímos até aqui (golden files, Testcontainers, baseline
de SQL, guarda de N+1) responde "o comportamento mudou?". Isso é
necessário, mas não suficiente para tirar o humano do loop — porque
prova só o que o teste pensou em testar. As sugestões abaixo atacam
duas lacunas diferentes: **a força da própria rede de segurança** (como
saber se ela é boa o suficiente para confiar sem olhar) e **o que
acontece quando ela falha silenciosamente** (o que existe depois do
merge, não só antes).

### B1. Mutation testing como critério de ENTRADA — rode CEDO, não depois de uma modernização completa

Cobertura de linha (`jacoco`, já presente no kit) mede se o código foi
executado — não se o teste pegaria uma mudança de comportamento. Um
teste pode "cobrir" uma linha e não afirmar nada sobre o resultado.

**Proposta:** antes de qualquer serviço ser elegível para
`nivel_autonomia_permitido: auto_merge_apos_guardrails`, rodar mutation
testing (`org.pitest:pitest-maven` para Maven, `info.solidsoft.pitest`
para Gradle) sobre a rede de segurança construída aqui (golden files +
Testcontainers). Mutation score baixo (ex: < 70%) é sinal objetivo de
que os testes existem mas não afirmam o suficiente — nesse caso, o
serviço fica em `revisao_humana_por_onda` até a rede de segurança
melhorar. Isso vira critério de entrada mensurável, não julgamento
subjetivo de "os testes parecem bons".

**⚠️ Se este serviço também está passando por modernização de versão
(via `java-modernization-kit`), a posição no processo importa — rode
isto ANTES da Onda 1 daquele kit (upgrade de Java), não depois da
Onda 4 (tudo migrado).** O que o mutation
score mede — se os testes pegam bug na lógica de negócio — é
praticamente independente da versão do JDK: mesma lógica, mesmos
testes, só compilados diferente. Rodar cedo, ainda no Java original do
serviço, dá a mesma garantia e evita depender de uma cadeia de
ferramentas mais nova e menos madura no destino da migração.

**Achado real de teste (piloto `ecommerce`, 22/07/2026):** PIT rodado
**depois** de todas as ondas (Java 25 + Gradle 8.14) resultou em
`0% de cobertura, 0 testes examinados` — não por falha da rede de
segurança, mas por incompatibilidade de infraestrutura: o plugin do
Gradle não respeita toolchain (roda com o JVM que iniciou o Gradle,
não o selecionado para compilar — `szpak/gradle-pitest-plugin#301`,
`#338`), e Gradle 8.x não consegue nem rodar o próprio daemon sob Java
25 (`gradle/gradle#35111`, status `closed:not-fixed`). Se este piloto
tivesse rodado o PIT antes da Onda 1 (ainda em Java 19), esse problema
inteiro não existiria — é exatamente o motivo desta reordenação.

**Implementado:** `context/guardrails/pom-pitest-snippet.xml` e
`context/guardrails/build-gradle-pitest-snippet.gradle` — configuração
pronta para copiar, não testada contra Maven Central/plugin repository
real (ver `context/guardrails/README.md` para o que confirmar antes de
usar em CI, incluindo o achado acima).

### B1b. Complemento — property-based testing (garantia diferente, não substitui B1)

Mutation testing (B1) mede se os testes **existentes** pegariam um bug
comum. Não testa entrada que ninguém pensou em escrever. Golden files
deste kit usam fixture única e fixa (`"Bruno"`, `AB1234`) — cobre a
estrutura, não o espaço de valores possíveis (unicode, limites
numéricos, nulos em combinação inesperada).

**Property-based testing** (`jqwik`, extensão de JUnit 5) gera
centenas de entradas aleatórias/extremas por execução e verifica
invariantes ("serializar e desserializar sempre preserva o valor",
"preço nunca fica negativo após qualquer sequência de operação"), em
vez de comparar contra um valor fixo. Garantia complementar, não
sobreposta: B1 responde "meus testes pegariam um bug conhecido?",
`jqwik` responde "meu código aguenta entrada que eu não imaginei?".

**Vantagem prática sobre o PIT, relevante após o achado acima:**
`jqwik` roda como dependência de teste normal, no mesmo JVM do
toolchain do projeto — **sem processo separado, sem o problema de
JVM incompatível que derrubou o PIT no `ecommerce`**. Funciona
igualmente bem antes ou depois da migração de Java.

Não implementado neste kit ainda (sem snippet pronto) — registrado
como direção validada em discussão, não como artefato testado.



### B2. Linter determinístico de escopo de diff — não depende de IA

O guardrail mais barato e mais confiável não usa IA nenhuma: um script
que inspeciona o diff de cada commit de onda e **falha o pipeline** se
o padrão de arquivos tocados não bater com o esperado para aquele tipo
de onda.

```
Onda "golden-files"     -> só pode tocar src/test/** e golden/**
Onda "java-toolchain"   -> só pode tocar build.gradle/pom.xml e settings
Onda "boot-major"       -> pode tocar build + main, NUNCA golden/**\.json
                            nem sql-baseline/**\.sql (esses só mudam
                            com decisão humana explícita, regra 3)
```

Isso não julga se a mudança é boa — só confirma que o agente não saiu
do escopo que a onda deveria ter. Zero ambiguidade, zero custo de
inferência, roda em segundos como step de CI antes de qualquer outra
coisa. É o tipo de guardrail que vale existir mesmo que tudo mais
funcione perfeitamente, porque não degrada como um "juiz" baseado em
IA pode degradar.

**Implementado e testado de verdade** (4 cenários confirmados: dentro
do escopo, fora do escopo, violação de `deny` mesmo com `allow` amplo,
branch sem onda configurada) — `scripts/diff_scope_linter.py` +
`context/guardrails/scope-rules.json`. Ver
`context/guardrails/README.md` para uso e wiring no GitLab CI.

### B3. Checagem de requisito não-funcional — o runbook hoje só cobre funcional

Golden files e Testcontainers prova que o **resultado** não mudou. Não
prova nada sobre latência, uso de memória, comportamento sob
concorrência — exatamente os requisitos não-funcionais que você
mencionou.

**Proposta:** para serviços em `auto_merge_apos_guardrails`, adicionar
um passo de checagem de performance simples antes/depois de cada onda
que mexe em runtime (Java version, Boot major): um load test leve
(k6, Gatling, ou até um loop de requisições cronometrado) contra a
mesma instância via Testcontainers, com threshold automático (ex:
p95 não pode piorar mais que X%). Não precisa ser sofisticado — precisa
existir, porque hoje literalmente nada no kit atesta isso.

**Status real (24/07/2026):** uma primeira tentativa de onda concreta
foi escrita e depois **removida deliberadamente** — não por a ideia
estar errada, mas porque a estratégia de dado de teste (sintético vs.
volume real vs. distribuição real) e o problema de acoplamento entre
microsserviços independentes (um serviço depende de massa gerada por
outro) precisam de mais maturidade antes de virar prompt file
prescritivo. Retomar depois de avaliar ferramentas (k6, Gatling,
JMeter, Locust, Artillery comparados) e decidir a estratégia de dado
caso a caso — não existe resposta única que sirva para todo serviço.

### B4. Guarda de rollback como pré-condição, não reação

Para qualquer serviço com merge automático permitido, exigir que o
pipeline confirme **antes** de mergear que existe caminho de rollback
testado (versão anterior da imagem ainda disponível, comando de
rollback validado) — não como algo que se descobre depois que algo deu
errado. Isso desloca parte da garantia de "prevenir erro" para
"recuperar rápido de erro", que é mais realista quando não há humano
olhando cada onda de perto.

### B5. Fora do escopo por restrição de programa: zero interferência em produção

**Decisão do programa: nenhuma automação pode interferir em produção.**
Isso elimina canário por completo, e reduz shadow traffic a caso
marginal — vale registrar o porquê, para que essa decisão não pareça
esquecimento na próxima revisão deste documento.

**Canário** (fatia real de tráfego de usuário servida pela versão
nova, com rollback automático por SLO) tem impacto real em produção
por definição — usuário de verdade pode sentir um bug da versão nova,
mesmo que contido. Incompatível com a restrição do programa. **Fora
do roadmap.**

**Shadow traffic** (espelha requisição real para a versão nova, nunca
serve a resposta ao usuário — quem responde continua sendo a versão
antiga) parece não afetar o usuário, mas tem uma pegadinha real:
**se o endpoint espelhado tem efeito colateral (grava banco, envia
e-mail, publica evento, cobra pagamento), a versão sombra executa
esse efeito de verdade**, mesmo com a resposta descartada. Em um
serviço como o piloto (`ecommerce`), espelhar `POST /product` faria a
versão sombra gravar um registro duplicado real no banco; espelhar
qualquer coisa envolvendo `PaymentHistoric` seria pior ainda.

Só seria cogitável em endpoints de leitura pura, sem efeito colateral
(`GET`, idempotentes) — e mesmo assim exige infraestrutura de
espelhamento de tráfego (service mesh, gateway com essa capacidade)
que não está confirmada como existente. Dado o risco residual e a
complexidade, **não é recomendado como próximo passo** — fica só
registrado aqui como o motivo de ter sido descartado, não como algo
com plano de implementação.

**Consequência prática de não ter nenhum guardrail pós-deploy:** todo
o peso da garantia recai sobre os itens pré-merge (B1-B4, B6). Não
existe rede de segurança depois que o código já está em produção —
reforça ainda mais a importância de B1 (mutation testing) e da rede
de segurança da Onda 2 estarem genuinamente fortes antes de qualquer
autonomia ser concedida.

### B6. Revisão automatizada como segunda camada, não substituto do B2

Um segundo agente (ou o mesmo modelo, contexto novo) revisando o diff
do primeiro contra as regras do `AGENTS.md` é uma camada adicional
razoável — mas é verificação probabilística, não determinística. Vale
como camada extra sobre o B2 (linter de escopo), nunca no lugar dele.
Não usar como único guardrail para decidir merge automático.

### Onde isso deixa a decisão de `nivel_autonomia_permitido`

Sugestão de critério mínimo para um serviço qualificar para
`auto_merge_apos_guardrails` (todos precisam ser verdadeiros, não
maioria):

```
[ ] criticidade = baixa (atribuída por humano, ficha do serviço)
[ ] porte = pequeno ou medio
[ ] mutation score da rede de seguranca >= limiar definido (B1)
[ ] linter de escopo de diff configurado para as ondas deste arquetipo (B2)
[ ] checagem de NFR configurada, se a onda mexe em runtime (B3)
[ ] rollback testado e documentado (B4)
```

Serviço de criticidade alta ou porte grande: `revisao_humana_por_onda`
sempre, independente de quantos guardrails existirem — a economia de
automação vale menos que o risco ali, e é exatamente a exceção que
você já tinha em mente.

---

