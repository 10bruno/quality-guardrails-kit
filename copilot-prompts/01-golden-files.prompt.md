---
agent: 'agent'
description: 'Golden files de serializacao (round-trip) -- REST e eventos'
---
Execute a onda de golden files: rede de segurança de serialização.

**O que este kit garante como produtor:** que o formato de qualquer
coisa que este serviço **emite** — resposta de API, evento publicado —
não muda sem alguém perceber. Isto é responsabilidade nossa como
produtor, **independente de sabermos quem consome** (teste de contrato
alinhado com consumidor específico, tipo Pact, é coisa diferente,
fora de escopo — exigiria coordenar com times que nem sempre temos
acesso). Golden file responde "eu mudei o que produzo?", não "isso
ainda serve para quem consome?".

**Passo 1.** Identifique DOIS tipos de classe em risco:

- **DTOs de REST:** classes usadas como `@RequestBody`/retorno em
  endpoints `POST`/`PUT`/`GET`, especialmente as anotadas
  `@Data @Builder` (Lombok) sem nenhuma anotação Jackson explícita
  (`@JsonCreator`, `@Jacksonized`, etc.) — esse padrão é o que mais
  frequentemente quebra na migração para Jackson 3.
- **Payload de evento:** classes usadas em `KafkaTemplate.send(...)`
  ou como parâmetro de método anotado `@KafkaListener` — mesmo risco
  de serialização, com uma diferença importante de consequência (ver
  nota abaixo).

**⚠️ Evento tem consequência mais séria que API síncrona se o formato
mudar.** Numa API REST, cliente e servidor normalmente são atualizados
perto um do outro no tempo. Evento Kafka pode ficar na fila minutos ou
dias — um consumidor que ainda não atualizou pode tentar ler um
formato novo. Trate mudança de formato de evento com mais cautela:
se o golden file de um evento quebrar, é sinal mais forte para parar e
envolver um humano do que o mesmo tipo de quebra numa DTO de REST.

**Passo 2.** Para cada classe identificada (REST ou evento), escreva
um teste `@JsonTest` com `JacksonTester`, cobrindo **sempre os dois
sentidos**:
```java
@JsonTest
class XGoldenTest {
    @Autowired private JacksonTester<X> json;

    @Test
    void serializacao_naoMudou() throws Exception {
        assertThat(json.write(fixture())).isEqualToJson(new ClassPathResource("golden/x.json"));
    }

    @Test
    void roundTrip_preservaTiposEValores() throws Exception {
        var jsonContent = json.write(fixture()).getJson();
        var desserializado = json.parseObject(jsonContent);
        // asserts campo a campo -- para BigDecimal use isEqualByComparingTo, nao isEqualTo
    }
}
```
**O teste de round-trip não é opcional.** Ele existe porque há bug
real e confirmado no Jackson 3 (creator implícito quebrado para
`@Data @Builder`) que só quebra na desserialização — a serialização
continua idêntica. Um golden file sem round-trip não detecta isso.

**Para payload de evento, confirme antes se o `ObjectMapper` usado no
Kafka é o mesmo da REST.** Serviços às vezes configuram um
`JsonSerializer`/`JsonDeserializer` próprio para o
`spring.kafka.producer`/`consumer`, com features do Jackson diferentes
do `ObjectMapper` padrão da aplicação. Se for diferente, o `@JsonTest`
usando o `ObjectMapper` padrão não reflete o comportamento real do
Kafka — nesse caso, configure o teste para usar o mapper real do
Kafka, não assuma que são o mesmo.

**Passo 3.** Nunca chute o JSON esperado. Escreva primeiro um teste de
descoberta (imprime o JSON real gerado), rode, confirme o formato real
(datas, decimais), só então fixe o arquivo `golden/x.json` definitivo
e apague o teste de descoberta.

**Use sempre a pasta `golden/` dedicada, nunca o padrão "mesmo pacote
do teste" que é a convenção oficial do Spring Boot.** Isso é decisão
deliberada deste kit, não desconhecimento da convenção oficial — ver
`context/piramide-de-testes.md` para o porquê (resumo: torna a regra
do `diff_scope_linter.py` simples de escrever e o diff fácil de
auditar). Não "corrija" isso para o padrão oficial por conta própria.

**No Windows, ao criar os arquivos `.json`:** não use `Out-File
-Encoding utf8` do PowerShell — insere BOM e quebra o parser JSON.
Use `[System.IO.File]::WriteAllText(caminho, conteudo,
[System.Text.UTF8Encoding]::new($false))`.

**Pare antes de commitar.** Reporte, na MESMA mensagem: quais DTOs e
quais eventos foram cobertos, o resultado do build, **e o próximo
passo explícito** (`/02-testcontainers`, após o merge confirmado — não
deixe essa informação de fora do relatório). Aguarde confirmação
antes de qualquer commit.
