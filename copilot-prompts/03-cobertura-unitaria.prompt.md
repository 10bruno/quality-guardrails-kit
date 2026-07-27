---
agent: 'agent'
description: 'Onda de cobertura unitaria: identifica regra de negocio sem teste puro, aplica o semaforo 90/95'
---
Execute a onda de cobertura de teste unitário.

**Passo 1.** Identifique lógica de negócio real neste serviço — cálculo,
validação de regra, máquina de estado — que hoje só é exercitada
indiretamente (via golden file ou Testcontainers) ou não é exercitada
por teste nenhum. Não confunda com CRUD simples sem regra própria —
se o serviço realmente não tem lógica não trivial, reporte isso e
pare, não invente teste artificial só para gerar cobertura.

**Passo 2.** Escreva testes unitários **puros** — sem `@SpringBootTest`,
sem Spring context nenhum, sem banco, sem HTTP. Só a classe/método
sendo testado, instanciado diretamente, em milissegundos.

**Passo 3.** Rode o relatório de cobertura:
```
./gradlew jacocoTestReport   (ou mvn jacoco:report)
```

**Passo 4.** Aplique o gate:
```
python3 scripts/coverage_gate.py --report build/reports/jacoco/test/jacocoTestReport.xml
```
(ajuste o caminho se for Maven: `target/site/jacoco/jacoco.xml`)

- 🟢 >= 95%: reporte e siga
- 🟡 90-94%: reporte, sinalize como aceitável mas não ideal, siga
- 🔴 < 90%: **não avance** — escreva mais testes até sair do vermelho,
  ou pare e reporte ao humano se a lógica restante for genuinamente
  difícil de isolar (nesse caso, é achado — regra 16 do `AGENTS.md`)

**Pare antes de commitar.** Reporte, na MESMA mensagem (não deixe para
depois): o percentual real, a cor, quais classes/métodos ganharam
teste novo, **e o próximo passo explícito** — se este for a última
onda automática deste kit (ver abaixo) ou se ainda falta algo. Aguarde
confirmação antes de qualquer commit.

**Próximo passo (inclua isto explicitamente no relatório acima, não
como nota separada):** esta é a última onda **automática** deste kit.
Se este serviço também está passando por modernização de versão (via
`modernization-kit`, repositório separado), o próximo passo é
voltar para lá — a rede de segurança agora está completa (golden
files, Testcontainers, cobertura unitária) para a Onda 3 daquele kit.

Existe ainda `/04-e2e-fluxo-critico` — **não é próximo passo
automático**, só rode se houver fluxo específico que justifique o
custo (o próprio prompt exige essa justificativa antes de qualquer
código). Mencione essa opção no relatório, sem recomendar
automaticamente.
