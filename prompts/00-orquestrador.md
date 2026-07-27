# Prompt 00 — Orquestrador de ondas (rede de segurança)

> Versão simplificada do orquestrador do `java-modernization-kit` —
> só duas ondas aqui, não precisa da mesma complexidade de sequência.

## O laço

```
1. Diagnóstico (copilot-prompts/00-scanner-diagnostico.prompt.md)
   -> determina o que já existe e o que falta

2. Gate de entrada:
   [ ] AGENTS.md copiado para a raiz do repositório do serviço

3. Para cada onda que falta (golden files, testcontainers):
   a. Baseline verde (clean build) antes de qualquer edição
   b. Aplica a mudança
   c. Classifica achado: mecânico (corrige) vs quebra de contrato
      (PARA, reporta) vs achado novo (categoria E, ver abaixo)
   d. Oráculo final: clean build completo
   e. PARE. Não commite sozinho. Apresenta diff + resultado do build.
   f. Após confirmação humana: commit, push, PR, PARE de novo até merge

4. Ao fim: atualiza a ficha do serviço, propõe achados novos ao kit
   (regra 16 do AGENTS.md)
```

## Categoria E — achado novo

Mesmo critério do kit de modernização: se um humano perguntasse "por
que isso quebrou e como resolvo", a resposta já existiria em algum
arquivo daqui? Se não, é achado novo — PR separado, neste repositório,
seguindo o formato já estabelecido em `context/achados/`.

**Se este serviço também usa o `java-modernization-kit`:** achado
sobre *versão específica* de Java/Boot/Jackson não pertence aqui — vai
para aquele repositório. Achado sobre *técnica de teste* fica aqui.

## Onde este laço PARA sempre

- Antes de qualquer commit, push ou merge
- Golden file mudou de bytes
- SQL baseline mudou
- Contagem de query (guarda N+1) mudou
- Mutation score caiu abaixo do limiar combinado
- Qualquer coisa em que consideraria escrever "provavelmente"

## Estado persistido

`context/servicos/<repo>.json` — mesmo schema documentado no
`RUNBOOK.md`, com os campos `criticidade`, `porte`,
`nivel_autonomia_permitido` decidindo o quanto de revisão humana este
serviço específico precisa (ver Anexo B do `RUNBOOK.md`).
