# Gera a evidência da concorrência. Abre DUAS sessões psql ao mesmo tempo (as "duas abas" do Query Tool) no banco
# matricula do container de teste bd2_teste_pg16 (nosso) e manda cada passo dos scripts 05b, 05c e 05d só para a aba
# que o script indica. Depois de cada passo anota o que cada aba mostrou e quantas sessões estão esperando trava.
# Com --extras mede também o que a comparação do README usa: travas de predicado do SERIALIZABLE e turmas diferentes.
# Uso: python -I concorrencia_evidencia.py <pasta local dos .sql> <pasta dos .sql no container> <saida.txt> [--extras]
import re
import subprocess
import sys
import threading
import time

LOCAL, NO_CONTAINER, SAIDA = sys.argv[1:4]
EXTRAS = "--extras" in sys.argv
C = "bd2_teste_pg16"
PAUSA = 1.5
PSQL = ["docker", "exec", "-i", C, "psql", "-U", "bd2", "-d", "matricula", "-X", "-v", "ON_ERROR_STOP=0"]
out = []


def sql_avulso(sql):
    r = subprocess.run(["docker", "exec", C, "psql", "-U", "bd2", "-d", "matricula", "-X", "-At", "-F", " | ", "-c", sql],
                       capture_output=True, text=True, encoding="utf-8")
    return (r.stdout + r.stderr).strip()


class Aba:
    def __init__(self, n):
        self.n, self.linhas, self.lidas = n, [], 0
        self.p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, encoding="utf-8", bufsize=1)
        threading.Thread(target=self._le, daemon=True).start()
        self.manda(f"\\set VERBOSITY verbose\nSET application_name = 'ABA {n}';")

    def _le(self):
        for linha in self.p.stdout:
            self.linhas.append(linha.rstrip("\n"))

    def manda(self, sql):
        self.p.stdin.write(sql + "\n")
        self.p.stdin.flush()

    def novas(self):
        n = self.linhas[self.lidas:]
        self.lidas += len(n)
        return [l for l in n if l.strip() and not l.startswith("LOCATION:")]

    def fecha(self):
        self.p.stdin.close()
        self.p.wait(timeout=30)


def travadas():
    r = sql_avulso("SELECT coalesce(string_agg(application_name, ', ' ORDER BY application_name), 'nenhuma') "
                   "FROM pg_stat_activity WHERE datname = 'matricula' AND wait_event_type = 'Lock'")
    return r


def anota(abas):
    time.sleep(PAUSA)
    for a in abas.values():
        for l in a.novas():
            out.append(f"[ABA {a.n}] {l}")
    out.append(f"   (esperando trava: {travadas()})")


def passo(abas, quem, cab, corpo):
    out.append("")
    out.append(cab)
    for k in quem:
        abas[k].manda(corpo)
        time.sleep(0.3)
    anota(abas)


TURMA = ("(SELECT t.id_turma FROM projeto_bd2.tb_turma t "
         "JOIN projeto_bd2.tb_disciplina d ON d.id_disciplina = t.id_disciplina "
         "JOIN projeto_bd2.tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo "
         "WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2 AND t.cd_turma = '{}')")


def situacao(cd="A"):
    return sql_avulso("SELECT t.qt_vagas || ' vagas, ' || count(m.id_matricula) || ' ocupadas, vagas_livres = ' "
                      "|| (t.qt_vagas - count(m.id_matricula)) FROM projeto_bd2.tb_turma t "
                      "LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa' "
                      f"WHERE t.id_turma = {TURMA.format(cd)} GROUP BY t.qt_vagas")


def limpeza():
    r = subprocess.run(["docker", "exec", C, "psql", "-U", "bd2", "-d", "matricula", "-X", "-v", "ON_ERROR_STOP=1",
                        "-f", f"{NO_CONTAINER}/05e_concorrencia_limpeza_v1.sql"],
                       capture_output=True, text=True, encoding="utf-8")
    ok = "ok" if r.returncode == 0 else f"ERRO rc={r.returncode}: {(r.stdout + r.stderr)[-300:]}"
    out.append(f"   limpeza (05e, numa terceira conexao): {ok} -> turma A com {situacao('A')}")


def blocos(arquivo):
    texto = open(f"{LOCAL}/{arquivo}", encoding="utf-8").read()
    partes = re.split(r"(?m)^(-- PASSO \d+ - [^\n]*)$", texto)
    yield [1, 2], "-- (inicio do arquivo, nas duas abas)", partes[0]
    for i in range(1, len(partes), 2):
        cab, corpo = partes[i], partes[i + 1]
        alvo = cab.split(":")[0]
        quem = [1, 2] if "ABA 1 e depois ABA 2" in alvo else [2] if "ABA 2" in alvo else [1]
        yield quem, cab, corpo


resumo = []
abas = {1: Aba(1), 2: Aba(2)}
time.sleep(1)
for a in abas.values():
    a.novas()

out.append("==================== preparacao ====================")
limpeza()
prep = open(f"{LOCAL}/05a_concorrencia_preparacao_v1.sql", encoding="utf-8").read()
passo(abas, [1, 2], "-- 05a_concorrencia_preparacao_v1.sql inteiro (F5), nas DUAS abas", prep)

for arq in ["05b_concorrencia_erro_v1.sql", "05c_concorrencia_solucao1_for_update_v1.sql",
            "05d_concorrencia_solucao2_serializable_v1.sql"]:
    out.append("")
    out.append(f"==================== {arq} ====================")
    if arq != "05b_concorrencia_erro_v1.sql":
        limpeza()
    inicio = len(out)
    for quem, cab, corpo in blocos(arq):
        passo(abas, quem, cab, corpo)
    trecho = "\n".join(out[inicio:])
    final = situacao("A")
    out.append("")
    out.append(f"   FINAL (terceira conexao): turma A com {final}")
    obs = []
    if "esperando trava: ABA 2" in trecho:
        obs.append("ABA 2 esperou a trava")
    if "40001" in trecho:
        obs.append("ABA 2 recebeu o erro 40001 e repetiu")
    resumo.append(f"{arq:48} {final}" + (f" ({', '.join(obs)})" if obs else ""))

limpeza()

if EXTRAS:
    out.append("")
    out.append("==================== medicoes extras para a comparacao (nao fazem parte da demonstracao) ====================")
    contagem = ("SELECT t.qt_vagas - count(m.id_matricula) AS vagas_livres FROM projeto_bd2.tb_turma t "
                "LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa' "
                "WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int GROUP BY t.qt_vagas;")

    def insert(aluno):
        return ("INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status) "
                "SELECT a.id_aluno, t.id_turma, now(), 'ativa'::projeto_bd2.tp_status_matricula "
                "FROM projeto_bd2.tb_aluno a, projeto_bd2.tb_turma t "
                f"WHERE a.cd_matricula = current_setting('projeto_bd2.{aluno}') "
                "AND t.id_turma = current_setting('projeto_bd2.turma_alvo')::int "
                "AND t.qt_vagas > (SELECT count(*) FROM projeto_bd2.tb_matricula m "
                "WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa');")

    out.append("")
    out.append("-- X1 - travas de predicado (SIReadLock) que a contagem de vagas pega no SERIALIZABLE")
    abas[1].manda("BEGIN ISOLATION LEVEL SERIALIZABLE;\n" + contagem)
    anota(abas)
    travas = sql_avulso("SELECT l.locktype || ' em ' || l.relation::regclass || ': ' || count(*) "
                        "FROM pg_locks l JOIN pg_stat_activity s ON s.pid = l.pid "
                        "WHERE s.application_name = 'ABA 1' AND l.mode = 'SIReadLock' "
                        "GROUP BY l.locktype, l.relation ORDER BY 1")
    out.append("   travas SIReadLock da ABA 1 (terceira conexao, pg_locks):")
    out.extend("      " + l for l in travas.splitlines())
    abas[1].manda("ROLLBACK;")
    anota(abas)

    out.append("")
    inicio_x2 = len(out)
    out.append("-- X2 - SERIALIZABLE com turmas DIFERENTES: ABA 1 na turma A, ABA 2 na turma B (CCO072 2026/2 B)")
    abas[2].manda(f"SELECT set_config('projeto_bd2.turma_alvo', {TURMA.format('B')}::text, false) AS turma_da_aba_2;")
    anota(abas)
    out.append(f"   antes: turma B com {situacao('B')}")
    for k in (1, 2):
        abas[k].manda("BEGIN ISOLATION LEVEL SERIALIZABLE;\n" + contagem)
        time.sleep(0.3)
    anota(abas)
    abas[1].manda(insert("aluno_a") + "\nCOMMIT;")
    anota(abas)
    abas[2].manda(insert("aluno_b") + "\nCOMMIT;")
    anota(abas)
    abas[2].manda("ROLLBACK;")
    anota(abas)
    out.append(f"   depois: turma A com {situacao('A')} | turma B com {situacao('B')}")
    x2 = "\n".join(out[inicio_x2:])
    resumo.append("X2 SERIALIZABLE turmas diferentes: " + ("ABA 2 recebeu 40001 (falso positivo)" if "40001" in x2
                                                         else "nenhuma das duas foi derrubada"))
    apaga = sql_avulso("DELETE FROM projeto_bd2.tb_matricula WHERE id_aluno IN (SELECT id_aluno FROM "
                       "projeto_bd2.tb_aluno WHERE cd_matricula IN ('26000001', '26000002')) AND id_turma IN "
                       f"({TURMA.format('A')}, {TURMA.format('B')})")
    out.append(f"   limpeza das turmas A e B: {apaga} -> turma A com {situacao('A')} | turma B com {situacao('B')}")

    out.append("")
    out.append("-- X3 - FOR UPDATE com turmas DIFERENTES: ABA 1 tranca a turma A, ABA 2 tranca a turma B")
    trava = ("BEGIN;\nSELECT id_turma, qt_vagas FROM projeto_bd2.tb_turma "
             "WHERE id_turma = current_setting('projeto_bd2.turma_alvo')::int FOR UPDATE;")
    abas[1].manda(trava)
    anota(abas)
    abas[2].manda(trava)
    anota(abas)
    x3 = out[-1]
    resumo.append("X3 FOR UPDATE turmas diferentes: " + ("ABA 2 esperou" if "ABA 2" in x3 else "ninguem esperou"))
    for k in (1, 2):
        abas[k].manda("ROLLBACK;")
    anota(abas)

    out.append("")
    inicio_x4 = len(out)
    out.append("-- X4 - o INSERT que confere a vaga, SEM o FOR UPDATE, nas duas abas antes de algum COMMIT (turma A)")
    abas[2].manda(f"SELECT set_config('projeto_bd2.turma_alvo', {TURMA.format('A')}::text, false) AS turma_da_aba_2;")
    anota(abas)
    limpeza()
    abas[1].manda("BEGIN;\n" + insert("aluno_a"))
    anota(abas)
    abas[2].manda("BEGIN;\n" + insert("aluno_b"))
    anota(abas)
    for k in (1, 2):
        abas[k].manda("COMMIT;")
        time.sleep(0.3)
    anota(abas)
    final_x4 = situacao("A")
    out.append(f"   depois: turma A com {final_x4}")
    resumo.append(f"X4 INSERT com conferencia, sem FOR UPDATE: turma A com {final_x4}")
    limpeza()

    out.append("")
    out.append("-- X5 - travas SIReadLock numa turma com ate 32 matriculas ativas (a turma 2026/2 com contagem mais perto de 25)")
    menor = sql_avulso("SELECT id_turma || ' | ' || count(*) FROM projeto_bd2.tb_matricula WHERE ds_status = 'ativa' "
                       "GROUP BY id_turma HAVING count(*) BETWEEN 20 AND 30 ORDER BY abs(count(*) - 25), id_turma LIMIT 1")
    id_menor, qt_menor = [p.strip() for p in menor.split("|")]
    out.append(f"   turma {id_menor}: {qt_menor} matriculas ativas")
    abas[1].manda(f"SELECT set_config('projeto_bd2.turma_alvo', '{id_menor}', false) AS turma_da_aba_1;\n"
                  "BEGIN ISOLATION LEVEL SERIALIZABLE;\n" + contagem)
    anota(abas)
    travas5 = sql_avulso("SELECT l.locktype || ' em ' || l.relation::regclass || ': ' || count(*) "
                         "FROM pg_locks l JOIN pg_stat_activity s ON s.pid = l.pid "
                         "WHERE s.application_name = 'ABA 1' AND l.mode = 'SIReadLock' "
                         "GROUP BY l.locktype, l.relation ORDER BY 1")
    out.append("   travas SIReadLock da ABA 1 (terceira conexao, pg_locks):")
    out.extend("      " + l for l in travas5.splitlines())
    abas[1].manda("ROLLBACK;\n"
                  f"SELECT set_config('projeto_bd2.turma_alvo', {TURMA.format('A')}::text, false) AS turma_da_aba_1;")
    anota(abas)
    resumo.append(f"X5 SERIALIZABLE turma com {qt_menor} ativas: "
                  + ("trava na tabela tb_matricula inteira" if "relation em projeto_bd2.tb_matricula" in travas5
                     else "sem trava na tabela tb_matricula inteira"))

for a in abas.values():
    a.fecha()

open(SAIDA, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n\nRESUMO\n" + "\n".join(resumo) + "\n")
print("\n".join(resumo))
