# A pirâmide de testes deste kit — o que cada peça garante, e o que falta

> Documento para apresentação. Linguagem direta, exemplos reais tirados
> do piloto — não teoria abstrata.

## A pirâmide, em uma frase

Testes mais **baratos, rápidos e numerosos** ficam embaixo (unitário).
Testes mais **caros, lentos e realistas** ficam em cima (ponta a ponta).
A regra de ouro: teste o máximo possível embaixo; suba na pirâmide só
quando a camada de baixo não consegue provar o que você precisa provar.

```
        /\
       /  \        Ponta a ponta (poucos, lentos, caros)
      /----\
     /      \       Integração (Testcontainers)
    /--------\
   /          \     Unitário (regra de negócio pura)
  /------------\
```

Duas coisas do nosso kit **não entram nessa pirâmide** — são categorias
diferentes, explicadas no fim.

---

## Camada por camada — o que cada técnica garante

### 1. Golden files (round-trip) — `@JsonTest` + `JacksonTester`

**O que garante:** o formato exato dos dados que este serviço **produz**
(resposta de API REST, ou evento publicado num tópico Kafka) não muda
sem alguém perceber — garantia como **produtor**, independente de
sabermos quem consome. Isso é diferente de contract testing alinhado
com consumidor específico (ex: Pact), que exigiria coordenar com quem
consome — fora de escopo deste kit, decisão de organização.

**O que resolve:** biblioteca de serialização mudou de versão (Jackson
2→3, por exemplo) e silenciosamente alterou como uma data ou um número
é representado — algo que quebraria quem está do outro lado, sem
nenhum erro aparecer aqui.

**Como resolve:** pega um objeto de exemplo, serializa para JSON,
compara byte a byte contra um arquivo salvo. Depois faz o caminho
inverso — pega esse mesmo JSON, desserializa de volta, confirma que os
valores batem. As duas direções importam: já vimos, na prática, um bug
que só quebrava na volta (desserialização), nunca na ida.

**Cobre os dois: DTO de REST e payload de evento.** O mesmo mecanismo
(`@JsonTest`) serve para ambos — a diferença é só qual classe você
está testando. Payload de evento merece mais cautela se o golden file
quebrar: evento pode ficar na fila minutos ou dias, um consumidor que
ainda não atualizou pode ler o formato novo antes de estar pronto —
consequência mais séria que uma API síncrona, onde cliente e servidor
normalmente são atualizados perto um do outro no tempo.

**Exemplo real:**
```java
@JsonTest
class CustomerGoldenTest {
    @Autowired private JacksonTester<CustomerRequest> json;

    @Test
    void serializacao_naoMudou() throws Exception {
        assertThat(json.write(fixture())).isEqualToJson("golden/customer.json");
    }

    @Test
    void roundTrip_preservaOsDados() throws Exception {
        var jsonContent = json.write(fixture()).getJson();
        var desserializado = json.parseObject(jsonContent);
        assertThat(desserializado.getCpf()).isEqualTo("12345678910");
    }
}
```

**Decisão deliberada: pasta `golden/` dedicada, não o padrão oficial
do Spring.** A documentacao oficial do Spring Boot recomenda o arquivo
`.json` no MESMO PACOTE da classe de teste (resolvido automaticamente
via classpath), nao numa pasta separada --
`docs.spring.io` / secao "Auto-configured JSON Tests", exemplo oficial:
`assertThat(this.json.write(details)).isEqualToJson("expected.json")`,
com o arquivo vivendo em `src/test/resources/<mesmo pacote do teste>/`.

Fizemos diferente de proposito: usar uma pasta `golden/` dedicada (em
vez de espalhar pelo pacote de cada teste) torna trivial escrever a
regra do `diff_scope_linter.py` (`**/golden/**.json` como `deny`) e
torna o diff de uma onda visualmente obvio de auditar -- "mudou algo em
`golden/`? e zona sensivel", num lugar so, independente de estrutura
de pacote. E uma troca real: menos idiomatico para quem conhece o
padrao oficial do Spring, mais simples de proteger via automacao. Se
a organizacao preferir o padrao oficial no futuro, e mudanca de
convencao, nao de principio -- o mecanismo de golden file continua o
mesmo, so a localizacao do arquivo muda.

**Onde fica na pirâmide:** bem embaixo — perto do unitário. Usa uma
fatia mínima do Spring (só o `ObjectMapper` configurado de verdade),
não sobe banco, não sobe HTTP.

---

### 2. Testcontainers — persistência real

**O que garante:** a query que o Hibernate gera, o mapeamento
JPA, o comportamento específico do dialeto do banco (Postgres vs
MySQL) continuam corretos de verdade — não "corretos assumindo que o
banco se comporta como eu acho que se comporta".

**O que resolve:** troca de versão do Hibernate/driver que gera SQL
diferente, incompatibilidade de tipo entre Java e coluna do banco,
comportamento de `@GeneratedValue` que só aparece com o banco real
rodando — nada disso um mock de repositório pegaria.

**Como resolve:** sobe um container Docker real do banco (não H2, não
embedded), roda a aplicação contra ele de verdade, grava e lê dados
reais.

**Exemplo real:**
```java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class ProductPersistenceTest {
    @Container
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create"); // nunca create-drop
    }

    @Test
    void gravaELeProduct() {
        productRepository.saveAndFlush(fixture());
        var encontrado = productRepository.findById("AB1234");
        assertThat(encontrado).isPresent();
    }
}
```

**Onde fica na pirâmide:** no meio — integração real, mas ainda não
passa pela camada HTTP/Controller.

---

### 3. Baseline de SQL (dentro da onda de Testcontainers)

Não é camada própria — é **reforço** da onda acima, relevante
especificamente para troca de versão de ORM/Hibernate.

**O que garante:** o SQL exato gerado não muda silenciosamente.

**Como resolve:** intercepta cada SQL real via `StatementInspector`,
grava como arquivo de referência, compara em cada execução.

---

### 4. Guarda de N+1 (dentro da onda de Testcontainers)

Também reforço, não camada própria.

**O que garante:** o número de queries por operação não sobe escondido
(ex: uma mudança que fazia 1 SELECT passa a fazer 50 sem ninguém notar).

**Como resolve:** conta `SELECT`/`INSERT` reais por operação, com
número **exato** esperado (não "no máximo N" — pega aumento e queda).

---

### 5. Mutation testing (PIT)

**Isto não é uma camada nova da pirâmide — é um termômetro que mede a
qualidade das camadas 1-4 acima.**

**O que garante:** que os testes que já existem **realmente
perceberiam** um bug comum, não só "rodam sem dar erro". Cobertura de
linha (`jacoco`) mede se o código executou; mutation testing mede se
alguém **notaria** se ele estivesse errado.

**Como resolve:** injeta centenas de bugs sintéticos no código
(inverte um `if`, troca um valor de retorno), roda a suíte contra cada
um. Se nenhum teste falha, esse bug "sobreviveu" — sinal de que a rede
de segurança tem buraco ali.

**Onde fica na pirâmide:** em lugar nenhum — é transversal, mede
qualquer camada abaixo dela, não é ela mesma uma camada.

---

### 6. Property-based testing (`jqwik`) — direção proposta, ainda não implementada

**O que garante:** comportamento correto em entradas que **ninguém
pensou em escrever manualmente** — valor limite, unicode, combinação
estranha mas válida.

**Como resolve:** em vez de um exemplo fixo (`"Bruno"`, `AB1234`),
gera centenas de valores aleatórios por execução e verifica um
invariante ("serializar e desserializar sempre preserva o valor",
independente de qual valor for).

**Onde fica na pirâmide:** tipicamente embaixo (unitário), mas é um
eixo **diferente** da pirâmide — pirâmide organiza por "quanto de
infraestrutura real está envolvida"; isto organiza por "como o caso de
teste é gerado" (fixo vs. aleatório). Os dois eixos são independentes.

---

## O que NÃO é teste, mesmo fazendo parte do kit

### `diff_scope_linter.py`

Não mede comportamento de código nenhum — é controle de **processo**:
confirma que o diff de uma onda ficou dentro do escopo esperado
(golden file não devia ter mudado numa onda de toolchain, por
exemplo). Categoria própria — guardrail de CI/governança, não pirâmide
de teste.

---

## Confrontando com a pirâmide — o que ainda falta

Sendo direto sobre as lacunas reais, não só o que já temos:

### 1. Teste unitário puro de regra de negócio — agora com gate formal

Golden files testam **serialização**. Testcontainers testa
**persistência**. Nenhum dos dois testa uma regra pura como "preço não
pode ficar negativo depois de um desconto" **isolada** de banco ou
HTTP — só a lógica, rodando em milissegundos, sem infraestrutura
nenhuma.

**Isso é lacuna real se o serviço tiver lógica de domínio não trivial**
(cálculo, validação de regra de negócio, máquina de estado). Para
CRUD simples sem regra própria, pode não haver muito o que testar
nessa camada — mas isso precisa ser confirmado caso a caso, não
assumido.

**Gate formal adotado, não só recomendação solta:** semáforo de
cobertura de linha (medida pelo `jacoco`, já presente no kit), aplicado
por `scripts/coverage_gate.py` — determinístico, testado (4 cenários
reais, incluindo confirmação de que lê o contador agregado certo, não
soma nível de pacote com nível de relatório por engano):

| Faixa | Cor | Efeito |
|---|---|---|
| >= 95% | 🟢 Verde | Meta ideal — nenhuma ação |
| 90% a 94% | 🟡 Amarelo | Aceitável, sinalizado — não bloqueia sozinho |
| < 90% | 🔴 Vermelho | Bloqueia o pipeline |

```bash
python3 scripts/coverage_gate.py --report build/reports/jacoco/test/jacocoTestReport.xml
```

Isto mede **cobertura de linha**, que é diferente de mutation testing
(B1) — cobertura confirma que o código **executou**; mutation testing
confirma que, se estivesse errado, **alguém perceberia**. Os dois são
complementares, não substitutos um do outro — um serviço pode ter 100%
de cobertura de linha e ainda assim ter testes fracos (que executam
mas não afirmam nada de útil).

### 2. Teste ponta a ponta via HTTP real — decisão do engenheiro, não automática

Golden file usa fatia estreita (nem sobe o MVC). Testcontainers testa
o `Repository` direto, sem passar pelo `Controller`. **Uma mudança na
camada HTTP** (anotação de validação, mapeamento de rota, exception
handler) pode não ser pega por nenhuma das duas camadas hoje.

`@SpringBootTest(webEnvironment = RANDOM_PORT)` +
`TestRestTemplate`/`WebTestClient`, batendo no endpoint real via HTTP,
banco real via Testcontainers por trás. Mais caro (sobe a aplicação
inteira), por isso fica no topo da pirâmide.

**Diferente das outras ondas deste kit, esta não é recomendada
automaticamente pelo scanner.** É cara demais para virar padrão em
todo endpoint — decisão consciente do engenheiro, sobre um fluxo
específico que ele julga crítico o suficiente para justificar o custo.
Ver `copilot-prompts/04-e2e-fluxo-critico.prompt.md` — o próprio prompt
começa perguntando **por que**, antes de qualquer código.

### 3. Resolvido: contrato como produtor (golden file), contrato com consumidor específico (fora de escopo)

Esclarecido em discussão com o time: **golden file já garante o que é
nossa responsabilidade** — que o formato do que produzimos (API ou
evento) não muda sem percebermos, independente de sabermos quem
consome. Isso agora cobre explicitamente payload de evento Kafka, não
só DTO de REST (ver item 1 acima).

O que continua fora de escopo, deliberadamente: garantir que o formato
bate com o que um consumidor **específico** espera (contract testing
tipo Pact, exigindo coordenação com quem consome). Decisão explícita:
muitos consumidores estão em outras áreas da empresa, fora do alcance
deste programa — esforço de alinhamento com cada um seria
desproporcional ao ganho, e não é responsabilidade que este kit se
propõe a cobrir.

### 4. Performance/carga — em standby, deliberadamente

Não é lacuna da pirâmide funcional (que é sobre "o resultado está
certo?") — é outro eixo inteiro ("o resultado chega rápido o
suficiente, sob quantos usuários simultâneos?").

Uma primeira tentativa de onda concreta foi escrita e removida
(24/07/2026) — não por a ideia estar errada, mas porque duas questões
reais precisam amadurecer antes: **estratégia de dado de teste**
(sintético puro vs. volume realista vs. distribuição real — cada um
resolve um problema diferente, nenhum serve para tudo) e
**acoplamento entre microsserviços independentes** (um serviço
depender de massa gerada por outro para gerar seu próprio teste de
carga — como isolar sem recriar em teste o mesmo acoplamento real que
existe em produção). Retomar depois de avaliar ferramentas (k6,
Gatling, JMeter, Locust, Artillery) e decidir a estratégia caso a
caso.
