#!/usr/bin/env python3
"""
diff_scope_linter.py

Verifica se os arquivos alterados numa branch de onda batem com o
escopo esperado para aquele tipo de onda (context/scope-rules.json).

Deterministico, sem IA, sem dependencia externa (so biblioteca padrao).
Pensado para rodar como step de CI (GitLab CI) antes de qualquer outra
checagem -- barato, rapido, sem ambiguidade.

Uso:
    python3 diff_scope_linter.py [--base main] [--rules scope-rules.json]

Codigo de saida:
    0 = ok (nenhuma violacao, ou onda nao configurada -- ver nota no
        proprio scope-rules.json sobre por que isso nao bloqueia)
    1 = violacao encontrada, ou erro de uso/configuracao
"""

import argparse
import fnmatch
import json
import subprocess
import sys


def get_current_branch() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def get_changed_files(base_ref: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base_ref}...HEAD"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"ERRO: nao consegui rodar 'git diff --name-only {base_ref}...HEAD'.")
        print(result.stderr.strip())
        print("Confirme que a branch base existe localmente (git fetch pode ser necessario em CI).")
        sys.exit(1)
    files = [f for f in result.stdout.strip().split("\n") if f]
    return files


def match_any(path: str, patterns: list[str]) -> str | None:
    """Retorna o padrao que bateu, ou None se nenhum bateu."""
    for pattern in patterns:
        if fnmatch.fnmatch(path, pattern):
            return pattern
    return None


def find_onda_rules(branch: str, rules: dict) -> tuple[str, dict] | None:
    """
    Casa o nome da branch contra as chaves de 'ondas' no rules.json.
    Aceita tanto nome exato quanto branch prefixada
    (ex: 'feature/onda-3-boot-major' ou so 'onda-3-boot-major').
    """
    ondas = rules.get("ondas", {})
    for onda_nome, onda_regras in ondas.items():
        if branch == onda_nome or onda_nome in branch:
            return onda_nome, onda_regras
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="main", help="branch base para comparar (default: main)")
    parser.add_argument("--rules", default="scope-rules.json", help="caminho do arquivo de regras")
    args = parser.parse_args()

    try:
        with open(args.rules, encoding="utf-8") as f:
            rules = json.load(f)
    except FileNotFoundError:
        print(f"ERRO: arquivo de regras '{args.rules}' nao encontrado.")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERRO: '{args.rules}' nao e JSON valido: {e}")
        sys.exit(1)

    branch = get_current_branch()
    matched = find_onda_rules(branch, rules)

    if matched is None:
        print(f"AVISO: branch '{branch}' nao corresponde a nenhuma onda configurada em '{args.rules}'.")
        print("Nao bloqueando -- onda nao configurada passa por padrao (ver nota no proprio arquivo de regras).")
        sys.exit(0)

    onda_nome, onda_regras = matched
    sempre_permitido = rules.get("sempre_permitido", [])
    allow = onda_regras.get("allow", [])
    deny = onda_regras.get("deny", [])

    changed_files = get_changed_files(args.base)
    if not changed_files:
        print(f"Nenhum arquivo alterado em relacao a '{args.base}'. Nada a checar.")
        sys.exit(0)

    print(f"Onda detectada: {onda_nome}")
    print(f"Arquivos alterados: {len(changed_files)}")
    print("")

    violations = []

    for path in changed_files:
        if match_any(path, sempre_permitido):
            continue

        denied_by = match_any(path, deny)
        if denied_by:
            violations.append((path, f"PROIBIDO explicitamente por '{denied_by}'"))
            continue

        if allow:
            allowed_by = match_any(path, allow)
            if not allowed_by:
                violations.append((path, f"fora do escopo permitido para '{onda_nome}'"))

    if violations:
        print(f"FALHOU: {len(violations)} arquivo(s) fora do escopo esperado para '{onda_nome}':")
        print("")
        for path, reason in violations:
            print(f"  {path}")
            print(f"    -> {reason}")
        print("")
        print("Se esta mudanca e legitima, ou o arquivo pertence a outra onda")
        print("(nao deveria estar neste commit), ou scope-rules.json precisa")
        print(f"ser atualizado para refletir o escopo real de '{onda_nome}'.")
        print("Atualizar o arquivo de regras e decisao humana, nao automatica.")
        sys.exit(1)

    print(f"OK: todos os {len(changed_files)} arquivo(s) alterado(s) estao dentro do escopo de '{onda_nome}'.")
    sys.exit(0)


if __name__ == "__main__":
    main()
