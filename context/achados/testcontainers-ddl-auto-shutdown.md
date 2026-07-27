# Testcontainers + ddl-auto=create-drop — corrida no shutdown

> Descoberto no piloto, teste de Testcontainers duplo (MySQL+Postgres).
> Build passou (`BUILD SUCCESSFUL`), mas ~1 minuto foi gasto em timeout
> de conexão *depois* dos testes já terem terminado.

## Sintoma

Log de shutdown (`ionShutdownHook`) mostra `HikariPool ... Connection is
not available, request timed out after 30000ms`, seguido de
`Connection to localhost:<porta> refused`, para cada `EntityManagerFactory`
configurado. Build ainda reporta sucesso — o teste em si passou antes
disso acontecer.

## Causa

`spring.jpa.hibernate.ddl-auto=create-drop` faz o Hibernate tentar
`DROP TABLE` quando o `ApplicationContext` fecha. Mas o `@Testcontainers`
do JUnit já derrubou os containers antes desse ponto — o Hibernate tenta
se conectar numa porta que não existe mais, espera o timeout completo do
HikariCP (30s por pool, um por `DataSource`), desiste, e só então o
shutdown continua.

## Correção

Trocar `create-drop` por `create` (ou `none`, se as tabelas já existirem
via outro mecanismo) no `@DynamicPropertySource` do teste:

```java
registry.add("spring.jpa.hibernate.ddl-auto", () -> "create");
```

O container inteiro é destruído de qualquer forma ao final do teste — não
há necessidade de o Hibernate limpar uma tabela num banco que está prestes
a desaparecer. Remove a corrida, remove o timeout, remove ~1 minuto de
build.

#### Efeito de não corrigir

Não é falha — o build continua reportando sucesso. O custo é
silencioso: ~1 minuto perdido por execução, sem nenhum sinal de alerta
óbvio (só aparece como `WARN`/`ERROR` no log de shutdown, depois do
resultado dos testes já ter sido exibido). Multiplicado pelas execuções
diárias de CI e locais ao longo da vida do serviço, o custo agregado é
real, mesmo que cada execução individual pareça inofensiva.

## Ação para o kit

Prompt `02-testcontainers.md` deve especificar `ddl-auto=create` (nunca
`create-drop`) como padrão para configuração de container efêmero de
teste — evita que os outros 349 serviços redescubram isso um por um.

## Achados adicionais (sessão de SQL baseline + guarda N+1)

**`spring.jpa.properties.*` via `@DynamicPropertySource` propaga para
múltiplos `EntityManagerFactory` construídos manualmente**, mesmo sem
cada `Config.java` chamar `.properties(...)` explicitamente — confirmado
empiricamente: um único `statement_inspector` registrado globalmente
capturou SQL corretamente nos dois bancos (Postgres e MySQL) do piloto,
com conteúdo diferente e correto por dialeto. O `EntityManagerFactoryBuilder`
autoconfigurado pelo Boot aplica essas properties de forma compartilhada.
Útil para qualquer serviço com desenho multi-datasource semelhante.

**`merge()` vs `persist()` com `@Id` atribuído manualmente:** quando a
entidade não usa `@GeneratedValue`, o `save()` do Spring Data JPA chama
`entityManager.merge()` (não `persist()`), porque não há como saber se o
registro é novo sem consultar. `merge()` faz um `SELECT` de existência
antes do `INSERT`. Isso é comportamento documentado do Spring Data, não
bug — mas gera 1 SELECT a mais do que a intuição sugere, e é candidato
comum a confusão de "N+1 falso positivo" se não for conhecido de
antemão. Vale conferir em todo serviço com ID manual antes de fixar
baseline de contagem de query.

*Por que o Spring Data não sabe se é novo:* com `@GeneratedValue`, um
`id` nulo significa inequivocamente "ainda não existe" — decisão
trivial. Com `id` atribuído manualmente, um valor não-nulo pode ser
tanto "objeto novo com id já definido pelo código" quanto "objeto
existente sendo atualizado" — ambíguo sem consultar o banco. Existe uma
saída — implementar a interface `Persistable<ID>` na entidade, com
`isNew()` definido explicitamente — que eliminaria o `SELECT` extra.
Não avaliado neste piloto; candidato a otimização futura se a contagem
de query em outros serviços tornar isso relevante.

**`StatementInspector` estático fica limitado se um teste cruzar dois
bancos na mesma operação** (ex: transação distribuída/saga tocando
Postgres e MySQL ao mesmo tempo) — a lista compartilhada mistura SQL dos
dois sem separação por origem. Não é problema em testes que tocam um
banco por vez (caso comum), mas documentar como limitação conhecida.

**Robustez de line-ending em baseline de texto (SQL, não só JSON):**
mesmo cuidado do BOM (regra 14 do AGENTS.md) se aplica aqui — usar join
fixo em `"\n"` ao gravar/comparar, e normalizar `\r\n`→`\n` ao ler o
arquivo esperado, evita que diferença de configuração `core.autocrlf`
entre dev Windows e CI Linux quebre a comparação.
