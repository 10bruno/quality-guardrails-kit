---
agent: 'agent'
description: 'Diagnostico do servico: arquetipo, integracoes, cobertura de rede de seguranca ja existente'
---
Diagnostique este repositório antes de qualquer onda de rede de
segurança. Este scanner não pressupõe nenhum upgrade de versão
acontecendo — funciona igual para um serviço já estável há anos.

**Passo 1 — varredura determinística.** Percorra o projeto e extraia:
- Build: Maven ou Gradle
- Versões atuais de Java, Boot, e das bibliotecas de teste (JUnit,
  Mockito) — necessário para saber que SINTAXE de teste escrever,
  não para decidir onda de upgrade nenhuma
- Stack web: `starter-web` vs `starter-webflux` vs nenhum
- Integrações: procure por Kafka, Oracle, Postgres, MySQL, Mongo, AWS
  SDK, Redis nas dependências declaradas
- Arquivos com múltiplos `@Bean` retornando `DataSource` (sinal de
  multi-datasource)
- `new ObjectMapper()` fora de `@Configuration`
- `embedded-kafka`, Mongo embarcado, ou H2 em escopo de teste (sinal
  de que a onda de Testcontainers ainda não foi feita, ou foi feita
  incompleta)
- **Classes de payload de evento:** procure `KafkaTemplate.send(...)`
  e parâmetros de método anotado `@KafkaListener` — essas classes
  entram no mesmo risco de golden file que DTO de REST, não são
  categoria separada
- **Cobertura já existente:** procure testes `@JsonTest`/`JacksonTester`
  com round-trip (não só serialização unidirecional) — tanto para DTO
  de REST quanto para payload de evento —, testes `@Testcontainers`
  reais para cada integração de dados encontrada, configuração de
  PIT/mutation testing já presente

**Passo 2 — interpretação.** Com os fatos brutos do passo 1, escreva
um resumo em prosa: qual o arquétipo deste serviço, quais integrações
reais existem, o que já está coberto de rede de segurança e o que
falta.

**Regras:**
- Toda afirmação cita evidência (arquivo:linha). Se não tem certeza,
  marque como "não determinado" — não invente.
- Não infira criticidade de negócio — isso vem de um humano.
- `@Primary`/`@Qualifier` são mecanismo de resolução do Spring, não
  indicam importância de negócio — não interprete como tal.

**Passo 3 — determine o PRÓXIMO PASSO REAL.**

| Onda | Já está feita se... | Comando |
|---|---|---|
| Golden files | Existe pelo menos um teste `@JsonTest`/`JacksonTester` com round-trip para os DTOs de request principais **e** para os payloads de evento publicados (se houver Kafka) | `/01-golden-files` |
| Testcontainers | Existe teste `@Testcontainers` real (não embedded) para cada integração de dados encontrada | `/02-testcontainers` |
| Cobertura unitária | Relatório JaCoCo mostra >= 90% de cobertura de linha (rode `scripts/coverage_gate.py` para confirmar a cor exata) | `/03-cobertura-unitaria` |

Se TODAS já estiverem feitas, diga isso claramente. "Este serviço já
tem rede de segurança completa para as integrações encontradas" é
resposta válida e esperada, não falha do diagnóstico.

**Nota se este serviço também está passando por modernização de
versão** (via `java-modernization-kit`, repositório separado): esta
ficha de diagnóstico serve de base para aquele processo também — não
precisa rodar dois scanners diferentes que descobrem os mesmos fatos
de versão duas vezes. Se o outro kit também está sincronizado aqui,
mencione isso no resumo.

**Saída:** resumo estruturado (comentário no chat, não precisa criar
arquivo) com: arquétipo, integrações encontradas, cobertura existente,
e o único próximo comando recomendado.

Não edite nenhum arquivo neste passo — é só leitura e diagnóstico.
