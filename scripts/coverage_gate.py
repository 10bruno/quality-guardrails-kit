#!/usr/bin/env python3
"""
coverage_gate.py

Le o relatorio XML do JaCoCo e aplica o semaforo de cobertura de
LINHA (nao branch/instrucao) definido pelo programa:

    >= 95%  -> VERDE   (ideal)
    >= 90%  -> AMARELO (aceitavel, mas sinalizado -- nao bloqueia)
    <  90%  -> VERMELHO (bloqueia o pipeline)

Deterministico, sem IA, sem dependencia externa (so biblioteca padrao
do Python). Mesmo principio do diff_scope_linter.py: julgamento
humano decide o limiar, o script so aplica com consistencia.

Uso:
    python3 coverage_gate.py --report build/reports/jacoco/test/jacocoTestReport.xml
    python3 coverage_gate.py --report target/site/jacoco/jacoco.xml   # Maven

Codigo de saida:
    0 = verde ou amarelo (nunca bloqueia sozinho no amarelo)
    1 = vermelho, ou erro de uso/arquivo nao encontrado
"""

import argparse
import sys
import xml.etree.ElementTree as ET


VERDE = 95.0
AMARELO = 90.0


def extrair_cobertura_de_linha(caminho_relatorio: str) -> tuple[int, int]:
    """Retorna (linhas_cobertas, linhas_perdidas) do nivel agregado do
    relatorio -- nao soma os niveis aninhados (package/class/method),
    que teriam o mesmo numero contado varias vezes."""
    try:
        tree = ET.parse(caminho_relatorio)
    except FileNotFoundError:
        print(f"ERRO: relatorio '{caminho_relatorio}' nao encontrado.")
        print("Rode 'gradlew jacocoTestReport' (ou 'mvn jacoco:report') antes.")
        sys.exit(1)
    except ET.ParseError as e:
        print(f"ERRO: '{caminho_relatorio}' nao e XML valido: {e}")
        sys.exit(1)

    root = tree.getroot()
    # Counters diretos do <report> raiz = agregado do projeto inteiro.
    # Counters dentro de <package>/<class>/<method> sao por-unidade --
    # nao usar esses, ou o numero fica contado multiplas vezes.
    for counter in root.findall("counter"):
        if counter.get("type") == "LINE":
            missed = int(counter.get("missed", 0))
            covered = int(counter.get("covered", 0))
            return covered, missed

    print(f"ERRO: nenhum counter tipo LINE encontrado no nivel raiz de '{caminho_relatorio}'.")
    print("Confirme se e um relatorio XML do JaCoCo valido (nao HTML).")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, help="caminho do jacoco.xml")
    parser.add_argument("--verde", type=float, default=VERDE, help=f"limiar verde (default {VERDE})")
    parser.add_argument("--amarelo", type=float, default=AMARELO, help=f"limiar amarelo (default {AMARELO})")
    args = parser.parse_args()

    covered, missed = extrair_cobertura_de_linha(args.report)
    total = covered + missed

    if total == 0:
        print("AVISO: relatorio nao tem nenhuma linha instrumentada (total=0).")
        print("Isso normalmente significa que nao ha classes de producao")
        print("cobertas pelo JaCoCo neste modulo -- confirme configuracao,")
        print("nao assuma que e cobertura 0% real.")
        sys.exit(0)

    percentual = (covered / total) * 100

    print(f"Cobertura de linha: {covered}/{total} = {percentual:.1f}%")
    print("")

    if percentual >= args.verde:
        print(f"\033[92mVERDE\033[0m — {percentual:.1f}% >= {args.verde}% (meta ideal atingida)")
        sys.exit(0)
    elif percentual >= args.amarelo:
        print(f"\033[93mAMARELO\033[0m — {percentual:.1f}% esta entre {args.amarelo}% e {args.verde}%.")
        print("Aceitavel, mas sinalizado -- nao bloqueia o pipeline sozinho.")
        print("Considere elevar a cobertura antes da proxima onda que mexer nesta area.")
        sys.exit(0)
    else:
        print(f"\033[91mVERMELHO\033[0m — {percentual:.1f}% < {args.amarelo}%.")
        print("Abaixo do minimo aceitavel. Pipeline bloqueado.")
        sys.exit(1)


if __name__ == "__main__":
    main()
