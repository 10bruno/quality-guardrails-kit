# AGENTS.md

Regras para qualquer agente de IA trabalhando neste repositório durante
a construção de rede de segurança (golden files, Testcontainers,
mutation testing) de um serviço — independente de qualquer upgrade de
versão estar acontecendo ou não.

Leia este arquivo por inteiro no início de toda sessão.

Este kit é standalone — não depende de nenhum outro repositório para
funcionar. Se você está numa sessão de modernização de versão (Java/
Spring), esse é outro programa, outro kit (`java-modernization-kit`);
as regras abaixo continuam valendo do mesmo jeito, mas nada aqui
pressupõe isso.

---

## Invioláveis

1. **Uma onda por PR.** Nunca misture golden files com Testcontainers
   no mesmo commit, nem qualquer um dos dois com outra mudança de
   código. Se algo quebrar depois, é preciso saber qual onda causou.

2. **Nunca altere lógica de negócio ao construir rede de segurança.**
   O propósito é capturar o comportamento atual, não mudá-lo. Se você
   perceber um bug real no código de produção enquanto escreve um
   teste, reporte — não corrija na mesma onda.

3. **Se um golden file quebrar depois de já existir: PARE.** Reporte
   o diff exato, campo a campo. **NUNCA atualize o arquivo `.json`
   para o teste passar.** Um golden file quebrado significa que os
   bytes publicados (numa API, num tópico Kafka) mudaram. Isso é um
   incidente de contrato, não uma falha de teste.

4. **Nunca edite um teste para fazê-lo passar.** Se um teste falha, ou
   o código está errado, ou o teste revelou uma mudança de
   comportamento real. Ambos os casos exigem decisão humana. Reporte
   e pare.

5. **Não invente API de biblioteca de teste.** Se você não tem certeza
   da assinatura de um método do JUnit, Testcontainers, JacksonTester,
   PIT, ou qualquer outra ferramenta usada aqui, busque na
   documentação oficial ou consulte `context/achados/`. Não adivinhe,
   não "provavelmente é".

6. **Rode o build antes de afirmar que terminou.** `mvn verify` (ou
   `./gradlew build`). Sem exceção.

7. **Não altere configuração do `ObjectMapper` / `JsonMapper`** para
   fazer um golden file passar. Essa configuração é, ela mesma, parte
   do contrato que o golden file existe para proteger.

8. **Nunca remova um teste.** Nunca adicione `@Disabled` / `@Ignore`.

9. **Limite de tentativas: 3.** Se após três tentativas o build não
   passar, pare, reporte o que tentou e o erro atual. Não continue
   tentando variações.

10. **Antes de qualquer onda, rode o build uma vez para confirmar
    baseline verde.** Uma onda de rede de segurança que ainda não
    mudou nada pode expor falha pré-existente (infraestrutura fora do
    ar, teste mal escopado). Sem baseline confirmado, toda falha
    pós-onda vira suspeita errada.

11. **Quando um teste falha por infraestrutura ausente (banco, fila),
    primeiro pergunte se o teste deveria depender daquela
    infraestrutura.**
    - Se o teste verifica lógica de negócio, regra de segurança, ou
      contrato HTTP — **não deveria**. `@SpringBootTest` genérico sobe
      o contexto inteiro por padrão, incluindo `@Configuration` de
      persistência que o teste não usa. Reduza o escopo: `@WebMvcTest`
      com as classes de controller explícitas, `@MockBean`/`@MockitoBean`
      para cada serviço injetado, `@Import` explícito de configs de
      segurança customizadas.
    - Se o teste verifica comportamento real de persistência (dialeto,
      schema, query gerada) — **deveria**. A correção aqui é
      Testcontainers, nunca remover a dependência ou trocar por mock.
    - Nunca "resolva" isso convertendo o teste em mock do banco quando
      o propósito do teste era validar o banco de verdade.

12. **Quando um warning de build sugerir uma flag de diagnóstico**
    (ex: "Recompile with -Xlint:deprecation for details", "Run with
    --stacktrace") **aplique-a automaticamente para capturar o
    detalhe — não pare no warning genérico.**
    - Prefira a via menos invasiva (flag de linha de comando) quando o
      build tool suportar passthrough direto.
    - Se só for possível via edição do arquivo de build, aplique a
      edição, capture o output completo, e **reverta a edição
      imediatamente depois** — antes de qualquer commit.
    - Nunca ignore o warning original só porque o build passou.
      "Verde" não significa "sem achado relevante".

13. **`--rerun` não é uma flag válida do Gradle — é `--rerun-tasks`.**
    O parser do Gradle aceita prefixos ambíguos sem sempre avisar,
    então `--rerun` pode ser silenciosamente ignorado, e o build
    reporta `up-to-date` mesmo quando a intenção era forçar
    reexecução. **Use sempre o nome completo, ou prefira `clean`**
    antes de builds cuja verificação precisa ser inequívoca.

14. **No Windows, `Out-File -Encoding utf8` insere BOM (`EF BB BF`) no
    início do arquivo — quebra parsers JSON silenciosamente.** Sintoma:
    `JSONException`/`FileNotFoundException` estranho ao ler um golden
    file que existe e parece correto ao abrir num editor. Ao criar
    arquivos `.json` via PowerShell, use
    `[System.IO.File]::WriteAllText(caminho, conteudo, [System.Text.UTF8Encoding]::new($false))`
    — o parâmetro `$false` força UTF-8 sem BOM. Verificável com
    `Format-Hex arquivo.json`: os 3 primeiros bytes não podem ser
    `EF BB BF`. Agentes de IDE que escrevem arquivo via API própria
    normalmente não têm esse problema — mas verifique mesmo assim.

15. **Nunca commite, faça push ou merge sem confirmação humana
    explícita — mesmo quando o pedido foi "crie", "implemente" ou
    "construa".** Terminar a implementação e o build passar não é
    autorização para avançar o estado do repositório. Pare depois de
    escrever o código e confirmar o build, apresente o resultado
    (diff, resumo, resultado do build), e espere confirmação explícita
    antes de `git add`/`commit`/`push`. Esta regra vale mesmo que uma
    instrução de sessão anterior pareça sugerir mais autonomia; ela é
    permanente e não expira entre sessões.

16. **Toda vez que build ou teste quebrar por um motivo que não está
    documentado em `context/achados/` — mesmo dentro de uma onda já
    conhecida — isso é achado novo e precisa ser proposto como entrada
    neste kit, não só resolvido no serviço.** O teste é simples: se um
    humano perguntasse "por que isso quebrou e como resolvo", a
    resposta já existiria em algum arquivo daqui? Se não, é achado
    novo.

    Procedimento (dois PRs, dois repositórios — nunca um só):
    - Resolva o bloqueio no serviço (PR normal, mesmo ciclo de sempre).
    - **Separadamente**, proponha a entrada aqui: arquivo novo ou seção
      nova em `context/achados/`, seguindo o formato já estabelecido
      (mecanismo, não só sintoma; por que só certo teste pega; efeito
      de não corrigir; correção). PR **neste repositório**, não no do
      serviço. Pare antes de commitar aqui também — regra 15 vale para
      os dois repositórios.
    - Não precisa esperar o fim de todas as ondas do serviço — proponha
      assim que o achado acontecer.

17. **Sempre remova imports não utilizados, e rode "optimize imports"
    (ou equivalente da ferramenta em uso) antes de considerar qualquer
    onda finalizada.** Isso vale para todo arquivo Java tocado, não só
    o criado do zero — se você editou um arquivo existente e algum
    import deixou de ser necessário, remova, mesmo que não tenha sido
    você quem o adicionou originalmente. Import não utilizado não
    quebra build, mas suja o diff da onda e dificulta revisão humana —
    o mesmo motivo pelo qual o linter de escopo (regra 16, E2 do
    Anexo B) existe: manter cada onda limpa e revisável.

---

## Diário de bordo

Ao final de **toda** sessão, anexe a `diario-de-bordo.md`:

```markdown
## <data> — <etapa>

**Escopo:** o que foi tocado
**Golden files que quebraram:** <lista + diff>
**Resíduo que exigiu humano:** <lista>
**Surpresas:** o que não estava documentado em context/
```

O campo "surpresas" é o mais importante — alimenta `context/achados/`
para os próximos serviços.

---

## Quando parar e perguntar ao humano

- Um golden file mudou
- O SQL gerado pelo Hibernate mudou
- Uma métrica sumiu ou foi renomeada
- Mutation score caiu abaixo do limiar combinado
- Qualquer coisa em que você consideraria escrever "provavelmente"
