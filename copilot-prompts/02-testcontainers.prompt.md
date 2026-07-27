---
agent: 'agent'
description: 'Testcontainers real + baseline SQL + guarda de N+1'
---
Execute a onda de Testcontainers: rede de segurança de persistência.

**Passo 1.** Identifique as integrações de dados reais deste serviço
(Postgres, MySQL, Mongo — via `@Configuration` que constrói
`DataSource`/`EntityManagerFactory`). Se usar `embedded-kafka`, H2 ou
Mongo embarcado em teste, isso precisa ser substituído — eles mascaram
diferença de dialeto/driver real.

**Passo 2.** Escreva um teste de integração com Testcontainers real
para cada banco, cobrindo o caminho de produção (grava e lê via os
mesmos `Repository`/`Config` que a aplicação usa):
```java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class XPersistenceTest {
    @Container
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");
    // ... outros containers conforme integracoes reais

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        // ... jdbc-url/username/password/driverClassName por datasource
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create"); // NUNCA create-drop
    }
}
```

**⚠️ `ddl-auto=create-drop` causa race condition no shutdown**
(Hibernate tenta `DROP TABLE` no container já derrubado pelo JUnit —
2 timeouts de 30s por execução, sem quebrar o build, mas custando
tempo real). Use sempre `create`.

**Passo 3.** Capture o SQL real gerado como baseline versionado — não
só "passou". Registre um `StatementInspector` via
`spring.jpa.properties.hibernate.session_factory.statement_inspector`
no mesmo `@DynamicPropertySource`, compare contra arquivo
`.sql` versionado. Isso é o baseline pré-Hibernate-7.

**Passo 4.** Adicione guarda de N+1: conte SELECT/INSERT por operação
com `assertThat(count).isEqualTo(N)` — contagem exata, não limite
superior. **Se a entidade tiver `@Id` atribuído manualmente (sem
`@GeneratedValue`), espere 1 SELECT a mais que o intuitivo** — o
`save()` do Spring Data chama `merge()`, não `persist()`, porque não
sabe se o registro é novo sem consultar. Não é bug.

**Pare antes de commitar.** Reporte, na MESMA mensagem: quais
integrações foram cobertas, o resultado do build, **e o próximo passo
explícito** (`/03-cobertura-unitaria`, após o merge confirmado — não
deixe essa informação de fora do relatório). Aguarde confirmação
antes de qualquer commit.
