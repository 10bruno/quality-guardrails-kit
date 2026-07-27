---
agent: 'agent'
description: 'Teste ponta a ponta via HTTP real -- OPT-IN, decisao do engenheiro, nao recomendado automaticamente pelo scanner'
---
**Antes de escrever qualquer código, responda (e registre a resposta
no commit final) — não prossiga sem isso:**

1. **Qual fluxo específico você está protegendo?** ("todo o serviço"
   não é resposta válida — precisa ser um fluxo nomeado: ex: "criação
   de pedido com pagamento", não "os endpoints".)
2. **Por que golden files (`/01-golden-files`) e Testcontainers
   (`/02-testcontainers`) não são suficientes para este fluxo?** Se a
   resposta for "não sei, vou rodar por garantia" — PARE. Este teste é
   caro (sobe a aplicação inteira, mais lento que as outras ondas) e
   não deveria existir sem motivo específico.
3. **O que especificamente pode quebrar que só apareceria testando
   via HTTP real** (não via `Repository` direto, não via `@JsonTest`)?
   Exemplos legítimos: encadeamento de múltiplos endpoints numa
   transação de negócio, comportamento de `@ExceptionHandler` sob
   condição real, efeito de filtro/interceptor que só roda no
   pipeline HTTP completo.

**Se as três respostas não estiverem claras, não escreva o teste.**
Reporte ao humano que a justificativa não ficou forte o suficiente,
em vez de escrever algo "por garantia".

---

**Só depois da justificativa, escreva o teste** — subindo a aplicação
de verdade, batendo no endpoint real via HTTP, banco real via
Testcontainers por trás:

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class PedidoComPagamentoE2ETest {

    @Container
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create");
        // ... demais propriedades do datasource real
    }

    @Autowired
    private TestRestTemplate restTemplate; // ou WebTestClient, se reativo

    @Test
    void criaPedidoEProcessaPagamento_fluxoCompleto() {
        var pedidoResponse = restTemplate.postForEntity("/pedido", fixture(), PedidoResponse.class);
        assertThat(pedidoResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);

        var pagamentoResponse = restTemplate.postForEntity(
            "/pedido/" + pedidoResponse.getBody().getId() + "/pagamento",
            fixturePagamento(), PagamentoResponse.class);
        assertThat(pagamentoResponse.getStatusCode()).isEqualTo(HttpStatus.OK);

        // confirma estado final no banco real, nao so a resposta HTTP
        var pedidoSalvo = pedidoRepository.findById(pedidoResponse.getBody().getId());
        assertThat(pedidoSalvo.get().getStatus()).isEqualTo(StatusPedido.PAGO);
    }
}
```

**Escopo mínimo, de propósito.** Um teste E2E por fluxo crítico
justificado — não um por endpoint. Se você se pegar escrevendo vários
destes cobrindo variações do mesmo fluxo, provavelmente algumas dessas
variações deveriam ser teste unitário ou de Testcontainers, mais
barato, não E2E.

**Pare antes de commitar.** Reporte, na MESMA mensagem: a justificativa
(as 3 respostas do início), o fluxo coberto, o resultado do build, **e
deixe explícito que esta onda não faz parte da sequência automática**
— rodar de novo, para outro fluxo, só se surgir nova justificativa
específica. Aguarde confirmação antes de qualquer commit.
