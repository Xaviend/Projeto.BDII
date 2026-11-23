#!/usr/bin/env bash
# Rodada do zero de TODO o projeto, na ordem do README, num banco "matricula" NOVO dentro do container de teste
# bd2_teste_pg16 (criado aqui se nao existir, sem porta publicada). Nunca toca no bd2_postgres do ambiente da aula.
# Regenera TODAS as evidencias: indices (04), concorrencia (05), consultas (06), administracao (07 e 08),
# seguranca (10 + mutantes), backup (11 + docs/backup_restauracao.md, casos A a D), cardinalidade minima e o F5 do
# pgAdmin no PostgreSQL 16 e no 17.
# Uso (Git Bash, na pasta do repositorio, Docker aberto): bash ferramentas/rodada_completa.sh
# Precisa das imagens postgres:16 e postgres:17 (o docker baixa se nao tiver) e do Python 3.
set -e
export MSYS_NO_PATHCONV=1
C=bd2_teste_pg16
REPO="$(dirname "$(dirname "$(realpath "$0")")")"
SP="${SAIDA_DIR:-${TMPDIR:-/tmp}/bd2_rodada}"
E="${E_DIR:-$REPO/evidencias}"
OUT="$SP/final"
B="$SP/backup_teste"
mkdir -p "$E"
rm -rf "$OUT" "$B"
mkdir -p "$OUT" "$B"

docker start $C >/dev/null 2>&1 || docker run -d --name $C -e POSTGRES_USER=bd2 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16 >/dev/null
until docker exec $C pg_isready -U bd2 -q 2>/dev/null; do sleep 1; done
sleep 3
until docker exec $C psql -U bd2 -d postgres -Atc "select 1" >/dev/null 2>&1; do sleep 1; done
docker exec $C rm -rf /tmp/final
docker exec $C mkdir -p /tmp/final
for f in "$REPO"/sql/*.sql; do docker cp "$f" $C:/tmp/final/ >/dev/null; done
docker exec $C psql -U bd2 -d postgres -q -c "DROP DATABASE IF EXISTS matricula WITH (FORCE);" -c "DROP DATABASE IF EXISTS matricula_restaurada WITH (FORCE);" -c "CREATE DATABASE matricula;"
# schema academico simulado, como o que vem no banco do professor (o backup do projeto nao pode mexer nele)
docker exec $C psql -U bd2 -d matricula -q -c "CREATE SCHEMA academico; CREATE TABLE academico.aluno_prof (id int); INSERT INTO academico.aluno_prof VALUES (1);"
QUANDO="$(date '+%d/%m/%Y %H:%M') (horario de Brasilia)"
VERSAO="$(docker exec $C psql -U bd2 -d matricula -Atc 'show server_version')"
P="psql -U bd2 -d matricula -X"

roda() { # script
  if docker exec $C sh -c "$P -v ON_ERROR_STOP=1 -f /tmp/final/$1.sql" > "$OUT/$1.txt" 2>&1; then st=ok; else st=ERRO; fi
  echo "$1: $st | FALHOU: $(grep -c 'FALHOU' "$OUT/$1.txt" || true) | ERROR: $(grep -c 'ERROR' "$OUT/$1.txt" || true) | OK: $(grep -c 'NOTICE:  OK' "$OUT/$1.txt" || true)"
  [ "$st" = ok ] || { tail -8 "$OUT/$1.txt"; return 1; }
}
limpa() { sed -e 's/^psql:[^ ]*: NOTICE:  //' -e 's/^psql:[^ ]*: //' | grep -v -E '^ fn_medir $|^-+$|^ $|^[(]1 row[)]$'; }
digital() { docker exec $C sh -c "psql -U bd2 -d $1 -X -v ON_ERROR_STOP=1 -At -F ' | ' -f /tmp/final/11_administracao_backup_conferencia_v1.sql" | grep ' | '; }
academico() { docker exec $C sh -c "psql -U bd2 -d $1 -X -Atc 'select count(*) from academico.aluno_prof'" 2>&1 | head -1; }

roda 01_modelo_fisico_v1
roda 02_testes_restricoes_v1

# ---------- 02: mutantes. Copia do banco so com o 01 (tst02_base); para cada restricao do schema, uma copia nova
# sem ela, e o 02 tem que dar FALHOU. Os dois ultimos: NOT NULL tirado e restricao nova sem teste (bloco 8).
echo "== mutantes do 02"
docker exec $C psql -U bd2 -d postgres -q -c "DROP DATABASE IF EXISTS tst02_base WITH (FORCE);" -c "CREATE DATABASE tst02_base TEMPLATE matricula;"
LISTA=$(docker exec $C psql -U bd2 -d tst02_base -X -At -F '|' -c "SELECT c.conname, CASE WHEN c.contypid <> 0 THEN format('ALTER DOMAIN projeto_bd2.%I DROP CONSTRAINT %I;', t.typname, c.conname) ELSE format('ALTER TABLE projeto_bd2.%I DROP CONSTRAINT %I;', r.relname, c.conname) END FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace LEFT JOIN pg_class r ON r.oid = c.conrelid LEFT JOIN pg_type t ON t.oid = c.contypid WHERE n.nspname = 'projeto_bd2' AND c.contype IN ('c', 'u', 'f', 'x') AND c.conname NOT IN ('uq_curriculo_id_curso', 'uq_turma_id_periodo') ORDER BY c.conname" | tr -d '\r')
LISTA="$LISTA
not_null_id_turma|ALTER TABLE projeto_bd2.tb_matricula ALTER COLUMN id_turma DROP NOT NULL;
restricao_nova_sem_teste|ALTER TABLE projeto_bd2.tb_sala ADD CONSTRAINT ck_sala_nova CHECK (qt_capacidade < 1000);"
: > "$OUT/mutantes_02.txt"
VIVOS02=0
while IFS='|' read -r nome cmd; do
  [ -z "$nome" ] && continue
  docker exec $C psql -U bd2 -d postgres -q -c "DROP DATABASE IF EXISTS tst02_m WITH (FORCE);" -c "CREATE DATABASE tst02_m TEMPLATE tst02_base;" </dev/null
  docker exec $C psql -U bd2 -d tst02_m -q -v ON_ERROR_STOP=1 -c "$cmd" </dev/null >/dev/null
  saida02=$(docker exec $C sh -c "psql -U bd2 -d tst02_m -X -v ON_ERROR_STOP=1 -f /tmp/final/02_testes_restricoes_v1.sql" </dev/null 2>&1 || true)
  r=$(printf '%s\n' "$saida02" | grep -oE 'FALHOU.*' | head -1 | cut -c1-170 || true)
  [ -z "$r" ] && r=$(printf '%s\n' "$saida02" | grep -oE 'ERROR:.*' | head -1 | cut -c1-170 || true)
  [ -z "$r" ] && { r="NENHUM FALHOU (mutante vivo)"; VIVOS02=$((VIVOS02 + 1)); }
  echo "$nome => $r" >> "$OUT/mutantes_02.txt"
done <<< "$LISTA"
docker exec $C psql -U bd2 -d postgres -q -c "DROP DATABASE IF EXISTS tst02_m WITH (FORCE);" -c "DROP DATABASE IF EXISTS tst02_base WITH (FORCE);"
echo "mutantes do 02: $(grep -c . "$OUT/mutantes_02.txt") | vivos: $VIVOS02"

roda 03_carga_v1
docker exec $C sh -c "$P -v ON_ERROR_STOP=1 -f /tmp/final/02_testes_restricoes_v1.sql" > "$OUT/02_depois_da_carga.txt" 2>&1
{
echo "EVIDENCIAS - TESTES DE RESTRICAO (sql/02_testes_restricoes_v1.sql)"
echo "Gerado em $QUANDO, PostgreSQL $VERSAO no Docker (imagem postgres:16), banco criado do zero na ordem do README."
echo "Esperado: 75 \"OK barrado\", 4 \"OK conferido\" e nenhum FALHOU, antes e depois da carga. Cada \"OK barrado\" ja"
echo "conferiu que quem barrou foi a restricao esperada (o nome dela esta na mensagem do banco)."
echo
echo "########## antes da carga (so o 01) ##########"
grep -E 'NOTICE:  OK|FALHOU' "$OUT/02_testes_restricoes_v1.txt" | sed -e 's/^psql:[^ ]*: NOTICE:  //' -e 's/^psql:[^ ]*: //'
echo
echo "Total: $(grep -c 'OK barrado' "$OUT/02_testes_restricoes_v1.txt") OK barrado | $(grep -c 'OK conferido' "$OUT/02_testes_restricoes_v1.txt") OK conferido | $(grep -c 'FALHOU' "$OUT/02_testes_restricoes_v1.txt" || true) FALHOU"
echo
echo "########## depois da carga (01 a 03) ##########"
echo "Total: $(grep -c 'OK barrado' "$OUT/02_depois_da_carga.txt") OK barrado | $(grep -c 'OK conferido' "$OUT/02_depois_da_carga.txt") OK conferido | $(grep -c 'FALHOU' "$OUT/02_depois_da_carga.txt" || true) FALHOU"
echo
echo "########## prova de que os testes pegam erro (mutantes) ##########"
echo "Cada linha: uma restricao do 01 tirada (numa copia do banco so com o 01) e o primeiro FALHOU que o 02 deu."
echo "As duas ultimas: o NOT NULL de tb_matricula.id_turma tirado, e uma restricao NOVA sem teste (o bloco 8 tem que"
echo "acusar). Ficam fora uq_curriculo_id_curso e uq_turma_id_periodo (contem a PK; o bloco 8 explica)."
cat "$OUT/mutantes_02.txt"
echo
echo "Mutantes: $(grep -c . "$OUT/mutantes_02.txt") | vivos (nenhum FALHOU): $VIVOS02"
} > "$E/testes_restricoes_v1.txt"

# ---------- 04: aba Messages (NOTICE, no stderr) e aba Data Output (resultados, no stdout em CSV) separadas
docker exec $C sh -c "$P -q -v ON_ERROR_STOP=1 -P format=csv -f /tmp/final/04_indices_v1.sql" > "$OUT/04_dados.csv" 2> "$OUT/04_mensagens.txt"
echo "04_indices_v1: ok | linhas de Messages: $(wc -l < "$OUT/04_mensagens.txt") | ERROR: $(grep -c 'ERROR' "$OUT/04_mensagens.txt" || true)"
{
echo "EVIDENCIAS - INDICES (modelagem fisica e desempenho)"
echo "Aba Messages do sql/04_indices_v1.sql: EXPLAIN (ANALYZE, BUFFERS) de cada consulta ANTES e DEPOIS do indice."
echo "Gerado em $QUANDO, PostgreSQL $VERSAO no Docker (imagem postgres:16), banco criado do zero"
echo "com os scripts 01 a 04 na ordem do README. Tempo (ms) muda de maquina para maquina; buffers quase nao mudam."
echo "buffers = paginas de 8 kB lidas (hit = da memoria, read = do disco)."
echo "O resumo (aba Data Output) esta em evidencias/resumo_indices_v1.csv."
sed -e 's/^psql:[^ ]*: NOTICE:  //' "$OUT/04_mensagens.txt"
} > "$E/explain_indices_v1.txt"
sed -n '/^consulta,ms_antes/,$p' "$OUT/04_dados.csv" > "$E/resumo_indices_v1.csv"
cat "$E/resumo_indices_v1.csv"

# ---------- 05: as duas abas ao mesmo tempo, com as medicoes extras da comparacao
python -I "$REPO/ferramentas/concorrencia_evidencia.py" "$REPO/sql" /tmp/final "$OUT/concorrencia_corpo.txt" --extras
{
echo "EVIDENCIAS - TRANSACOES E CONCORRENCIA (a ultima vaga da turma CCO072 2026/2 A: 35 vagas, 34 ocupadas)"
echo "Gerado em $QUANDO, PostgreSQL $VERSAO no Docker (imagem postgres:16), banco criado do zero"
echo "com os scripts 01 a 04 na ordem do README."
echo "Como foi gerado: duas sessoes psql abertas ao mesmo tempo no banco matricula, no papel das duas abas do Query Tool."
echo "Cada passo dos scripts 05b, 05c e 05d foi mandado so para a aba que o script indica, com 1,5 s entre um e outro."
echo "[ABA 1] e [ABA 2] = o que cada aba mostrou logo depois daquele passo."
echo "(esperando trava: ...) = sessoes paradas esperando uma trava naquele momento, lido de pg_stat_activity."
echo "A limpeza (05e) e a conferencia FINAL rodam numa terceira conexao. Erro aparece com o codigo (SQLSTATE) na frente."
echo "No fim, as medicoes X1 a X5 usadas na comparacao do README (nao fazem parte da demonstracao)."
echo
cat "$OUT/concorrencia_corpo.txt"
} > "$E/concorrencia_duas_abas_v1.txt"

roda 06_consultas_v1
{
echo "EVIDENCIAS - AS 10 CONSULTAS DO MARCO 1 (sql/06_consultas_v1.sql)"
echo "Gerado em $QUANDO, PostgreSQL $VERSAO no Docker (imagem postgres:16), banco criado do zero"
echo "com os scripts 01 a 05 na ordem do README. No pgAdmin, cada consulta se roda selecionando o trecho e F5."
echo
sed -e 's/^psql:[^ ]*: //' "$OUT/06_consultas_v1.txt"
} > "$E/consultas_v1.txt"

# ---------- cardinalidade minima: quantos "pais" ficam sem filho na carga (README, "Como ler a cardinalidade")
docker cp "$REPO/ferramentas/cardinalidade_minima.sql" $C:/tmp/final/ >/dev/null
{
echo "EVIDENCIAS - CARDINALIDADE MINIMA NA CARGA (modelo/ e README, \"Como ler a cardinalidade\")"
echo "Gerado em $QUANDO, PostgreSQL $VERSAO, banco criado do zero com os scripts 01 a 06."
echo "Consulta: ferramentas/cardinalidade_minima.sql. 0 = todo pai tem filho; mais de 0 = existe pai sem filho na carga."
echo
docker exec $C sh -c "$P -v ON_ERROR_STOP=1 -f /tmp/final/cardinalidade_minima.sql" | grep -v '^SET$'
} > "$E/cardinalidade_minima_v1.txt"

roda 07_administracao_views_v1
roda 08_administracao_auditoria_v1
roda 09_administracao_seguranca_v1
roda 10_administracao_seguranca_testes_v1
roda 11_administracao_backup_conferencia_v1

# ---------- 07 e 08: ganho da materialized view e do indice GIN
{
echo "EVIDENCIAS - ADMINISTRACAO E OPERACAO (Arthur Coupe)"
echo "Materialized view, view de vagas e indice GIN no JSONB (bonus), com EXPLAIN (ANALYZE, BUFFERS)"
echo "Gerado em $QUANDO, PostgreSQL $VERSAO no Docker (imagem postgres:16), banco criado do zero"
echo "com os scripts 01 a 11 na ordem do README. Tempo (ms) muda de maquina para maquina; buffers quase nao mudam."
echo "buffers = paginas de 8 kB lidas (hit = da memoria, read = do disco)."
echo
echo "########## sql/07_administracao_views_v1.sql (aba Messages) ##########"
sed -n '/=== 1 indicadores de CCO - NA HORA/,/=== 2 vagas.*VIEW ===/p' "$OUT/07_administracao_views_v1.txt" | limpa | sed '$d'
sed -n '/=== 2 vagas.*VIEW ===/,/Execution Time/p' "$OUT/07_administracao_views_v1.txt" | limpa
echo
echo "---------- resumo (aba Data Output) ----------"
sed -n '/consulta .*fase_1/,/ rows*)$/p' "$OUT/07_administracao_views_v1.txt"
echo
echo "---------- materialized view desatualizada ate o REFRESH (BLOCO 5, dentro de BEGIN ... ROLLBACK) ----------"
sed -n '/momento .*aprovados_na_tabela/,/ rows*)$/p' "$OUT/07_administracao_views_v1.txt"
echo
echo "########## sql/08_administracao_auditoria_v1.sql (aba Messages) ##########"
sed -n '/=== 5 log de um aluno.*ANTES/,/ixlog_fim_inexistente/p' "$OUT/08_administracao_auditoria_v1.txt" | limpa | sed '/^DO$/,$d'
echo
echo "---------- resumo (aba Data Output) ----------"
sed -n '/consulta .*ms_antes/,/ rows*)$/p' "$OUT/08_administracao_auditoria_v1.txt"
} > "$E/explain_administracao_v1.txt"

# ---------- backup e restauracao (docs/backup_restauracao.md), casos A a D
echo "== backup"
digital matricula > "$B/antes.txt"; tail -1 "$B/antes.txt"
docker exec $C sh -c "pg_dump -U bd2 -d matricula -n projeto_bd2 -Fc -f /tmp/matricula.dump"
docker exec $C sh -c "pg_dumpall -U bd2 --roles-only --no-role-passwords -f /tmp/papeis.sql"
docker cp $C:/tmp/matricula.dump "$B/matricula.dump" >/dev/null
docker cp $C:/tmp/papeis.sql "$B/papeis.sql" >/dev/null
SENHAS=$(grep -ci 'password' "$B/papeis.sql" || true)
echo "senha no papeis.sql (esperado 0): $SENHAS"
# caso A: banco separado
docker exec $C sh -c "createdb -U bd2 matricula_restaurada"
docker exec $C sh -c "psql -U bd2 -d matricula_restaurada -q -c 'CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;'"
docker exec $C sh -c "pg_restore -U bd2 -d matricula_restaurada --exit-on-error /tmp/matricula.dump"
digital matricula_restaurada > "$B/caso_a.txt"
diff "$B/antes.txt" "$B/caso_a.txt" && echo "IGUAL: caso A"
# caso B: apaga o schema e restaura no mesmo banco (sem --clean)
docker exec $C sh -c "psql -U bd2 -d matricula -q -v ON_ERROR_STOP=1 -c 'DROP SCHEMA projeto_bd2 CASCADE;'" 2>/dev/null
docker exec $C sh -c "pg_restore -U bd2 -d matricula --exit-on-error /tmp/matricula.dump"
digital matricula > "$B/caso_b.txt"
diff "$B/antes.txt" "$B/caso_b.txt" && echo "IGUAL: caso B"
ACAD_B=$(academico matricula)
# caso C: erro humano, volta ao backup com --clean --if-exists
docker exec $C sh -c "psql -U bd2 -d matricula -q -v ON_ERROR_STOP=1 -c \"DELETE FROM projeto_bd2.tb_log_matricula WHERE id_log_matricula <= 100; UPDATE projeto_bd2.tb_matricula SET ds_status = 'cancelada' WHERE id_matricula <= 50;\""
digital matricula | tail -1 > "$B/com_erro.txt"
docker exec $C sh -c "pg_restore -U bd2 -d matricula --clean --if-exists --exit-on-error /tmp/matricula.dump"
digital matricula > "$B/caso_c.txt"
diff "$B/antes.txt" "$B/caso_c.txt" && echo "IGUAL: caso C"
ACAD_C=$(academico matricula)
SEG_C=$(docker exec $C sh -c "psql -U bd2 -d matricula -X -f /tmp/final/10_administracao_seguranca_testes_v1.sql" 2>&1 | grep -cE 'NOTICE:  OK' || true)
# caso D: servidor novo e vazio (container temporario, sem porta publicada, removido no fim)
N=bd2_teste_restauro
docker rm -f $N >/dev/null 2>&1 || true
docker run -d --name $N -e POSTGRES_USER=bd2 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16 >/dev/null
until docker exec $N pg_isready -U bd2 -q 2>/dev/null; do sleep 1; done
sleep 2
docker exec $N mkdir -p /tmp/final
docker cp "$B/matricula.dump" $N:/tmp/matricula.dump >/dev/null
docker cp "$B/papeis.sql" $N:/tmp/papeis.sql >/dev/null
docker cp "$REPO/sql/11_administracao_backup_conferencia_v1.sql" $N:/tmp/final/ >/dev/null
docker cp "$REPO/sql/10_administracao_seguranca_testes_v1.sql" $N:/tmp/final/ >/dev/null
docker exec $N sh -c "psql -U bd2 -d postgres -q -f /tmp/papeis.sql" 2>&1 | grep -i error || true
docker exec $N sh -c "createdb -U bd2 matricula && psql -U bd2 -d matricula -q -c 'CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;'"
docker exec $N sh -c "pg_restore -U bd2 -d matricula --exit-on-error /tmp/matricula.dump"
docker exec $N sh -c "psql -U bd2 -d matricula -X -v ON_ERROR_STOP=1 -At -F ' | ' -f /tmp/final/11_administracao_backup_conferencia_v1.sql" | grep ' | ' > "$B/caso_d.txt"
diff "$B/antes.txt" "$B/caso_d.txt" && echo "IGUAL: caso D"
SEG_D=$(docker exec $N sh -c "psql -U bd2 -d matricula -X -f /tmp/final/10_administracao_seguranca_testes_v1.sql" 2>&1 | grep -cE 'NOTICE:  OK' || true)
docker rm -f $N >/dev/null
echo "container temporario removido: $(docker ps -a --filter name=$N --format '{{.Names}}' | wc -l) sobrando"
{
echo "EVIDENCIAS - BACKUP E RESTAURACAO"
echo "Ensaio de docs/backup_restauracao.md em $QUANDO, PostgreSQL $VERSAO, banco criado do zero com os scripts 01 a 11"
echo "e um schema academico simulado ao lado (como o do professor). Impressao digital = sql/11_administracao_backup_conferencia_v1.sql."
echo "Backup: pg_dump -n projeto_bd2 -Fc (so o schema do projeto) e pg_dumpall --roles-only --no-role-passwords"
echo "(linhas com senha no arquivo de papeis: $SENHAS)."
echo
echo "########## impressao digital ANTES do backup ##########"
cat "$B/antes.txt"
echo
echo "########## depois de cada restauracao (so a linha geral; o diff de todas as linhas deu vazio) ##########"
echo "caso A, banco separado matricula_restaurada : $(tail -1 "$B/caso_a.txt")"
echo "caso B, schema apagado e restaurado         : $(tail -1 "$B/caso_b.txt")"
echo "caso C, erro humano e volta ao backup       : $(tail -1 "$B/caso_c.txt")"
echo "caso D, servidor novo vazio                 : $(tail -1 "$B/caso_d.txt")"
echo
echo "controle (caso C, com o erro e antes de restaurar, tem que ser DIFERENTE):"
cat "$B/com_erro.txt"
echo
echo "schema academico intacto depois dos casos B e C (linhas em academico.aluno_prof, esperado 1): $ACAD_B e $ACAD_C"
echo "testes de seguranca (10) depois da restauracao, esperado 29 OK: caso C $SEG_C OK, caso D $SEG_D OK"
} > "$E/backup_restauracao_v1.txt"

# ---------- mutantes da seguranca: cada um estraga uma coisa, os testes do 10 tem que acusar, o script do projeto conserta
echo "== mutantes"
PM="docker exec $C psql -U bd2 -d matricula -X -v ON_ERROR_STOP=1"
S=projeto_bd2
declare -A MUT
MUT[A_historico_true]="ALTER POLICY pol_aluno_proprio_historico ON $S.tb_historico USING (true);"
MUT[B_matricula_true]="ALTER POLICY pol_aluno_proprias_matriculas ON $S.tb_matricula USING (true);"
MUT[C_cadastro_true]="ALTER POLICY pol_aluno_proprio_cadastro ON $S.tb_aluno USING (true);"
MUT[D_rls_off_historico]="ALTER TABLE $S.tb_historico DISABLE ROW LEVEL SECURITY;"
MUT[E_delete_secretaria]="GRANT DELETE ON $S.tb_matricula TO secretaria;"
MUT[F_log_aluno]="GRANT SELECT ON $S.tb_log_matricula TO aluno;"
MUT[G_vagas_invoker]="ALTER VIEW $S.vw_vagas SET (security_invoker = true);"
MUT[H_cpf_coordenacao]="GRANT SELECT (cd_cpf) ON $S.tb_aluno TO coordenacao;"
MUT[I_update_coluna_toda]="GRANT UPDATE ON $S.tb_matricula TO secretaria;"
MUT[J_log_nm_usuario]="GRANT INSERT (nm_usuario) ON $S.tb_log_matricula TO secretaria;"
MUT[K_schema_public]="GRANT USAGE ON SCHEMA $S TO PUBLIC; GRANT SELECT ON $S.vw_oferta TO PUBLIC;"
MUT[L_log_sem_trava]="DROP TRIGGER trg_log_so_pelo_gatilho ON $S.tb_log_matricula;"
MUT[M_email_coordenacao]="GRANT SELECT (ds_email, dt_nascimento) ON $S.tb_aluno TO coordenacao;"
MUT[N_execute_public]="GRANT EXECUTE ON FUNCTION $S.fn_atualizar_indicadores() TO PUBLIC;"
MUT[O_aluno_bypassrls]="ALTER ROLE aluno_26000012 BYPASSRLS;"
MUT[P_aluno_na_secretaria]="GRANT secretaria TO aluno_26000012;"
MUT[Q_policy_extra_update]="CREATE POLICY pol_tmp ON $S.tb_historico FOR UPDATE TO coordenacao USING (true);"
MUT[R_aluno_sem_nome_professor]="REVOKE SELECT (nm_professor) ON $S.tb_professor FROM aluno;"
MUT[S_nota_sem_log]="DROP TRIGGER trg_log_historico ON $S.tb_historico;"
MUT[T_log_retroativo]="GRANT INSERT (dt_ocorrencia) ON $S.tb_log_matricula TO secretaria;"
MUT[U_sequence_aluno]="GRANT USAGE ON SEQUENCE $S.tb_matricula_id_matricula_seq TO aluno;"
MUT[V_create_schema]="GRANT CREATE ON SCHEMA $S TO secretaria;"
MUT[W_grant_direto_aluno]="GRANT SELECT ON $S.tb_log_matricula TO aluno_26000012;"
MUT[X_policy_extra_publica]="CREATE POLICY pol_tmp2 ON $S.tb_aluno FOR SELECT TO PUBLIC USING (true);"
: > "$OUT/mutantes.txt"
for k in $(printf '%s\n' "${!MUT[@]}" | sort); do
  $PM -q -c "${MUT[$k]}" >/dev/null
  bruto=$($PM -f /tmp/final/10_administracao_seguranca_testes_v1.sql 2>&1 || true)
  saida=$(printf '%s\n' "$bruto" | grep -v 'RESULTADO' | grep -oE 'FALHOU \(teste [0-9]+\)|ERROR.*' | tr '\n' ' ' || true)
  fim=$(printf '%s\n' "$bruto" | grep -oE 'RESULTADO: [0-9]+ teste\(s\) com FALHOU' | head -1 || true)
  [ -n "$fim" ] && saida="$saida| $fim"
  case $k in
    G_*) restaura="ALTER VIEW vw_vagas SET (security_invoker = false) (o que o 07_administracao_views_v1.sql cria)"
         $PM -q -c "ALTER VIEW $S.vw_vagas SET (security_invoker = false);" >/dev/null 2>&1 ;;
    L_*|S_*) restaura="08_administracao_auditoria_v1.sql + 09_administracao_seguranca_v1.sql"
         $PM -q -f /tmp/final/08_administracao_auditoria_v1.sql >/dev/null 2>&1
         $PM -q -f /tmp/final/09_administracao_seguranca_v1.sql >/dev/null 2>&1 ;;
    *)   restaura="09_administracao_seguranca_v1.sql"
         $PM -q -f /tmp/final/09_administracao_seguranca_v1.sql >/dev/null 2>&1 ;;
  esac
  depois=$($PM -f /tmp/final/10_administracao_seguranca_testes_v1.sql 2>&1 || true)
  ok=$(printf '%s\n' "$depois" | grep -cE 'NOTICE:  OK' || true)
  echo "$k => ${saida:-NENHUM FALHOU (mutante vivo)}| restaurado com $restaura: $ok OK" | tee -a "$OUT/mutantes.txt"
done
: > "$OUT/mutantes_sql.txt"
for k in $(printf '%s\n' "${!MUT[@]}" | sort); do echo "$k: ${MUT[$k]}" >> "$OUT/mutantes_sql.txt"; done

{
echo "EVIDENCIAS - TESTES DE SEGURANCA (papeis, GRANT/REVOKE e RLS)"
echo "Saida do sql/10_administracao_seguranca_testes_v1.sql, gerada em $QUANDO, PostgreSQL $VERSAO,"
echo "banco criado do zero com os scripts 01 a 11 na ordem do README. Esperado: 29 OK, nenhum FALHOU e"
echo "a linha final \"RESULTADO: todos os testes deram OK\"."
echo
echo "########## PARTE 1 - demonstracao (aba Data Output) ##########"
sed -n '/quem_sou/,/^RESET/p' "$OUT/10_administracao_seguranca_testes_v1.txt" | grep -v -E '^(RESET|SET)$'
echo
echo "########## PARTE 2 - testes automaticos (aba Messages) ##########"
grep -E 'NOTICE:  (OK|FALHOU|RESULTADO)' "$OUT/10_administracao_seguranca_testes_v1.txt" | limpa
echo
echo "Total OK: $(grep -c 'NOTICE:  OK' "$OUT/10_administracao_seguranca_testes_v1.txt") | Total FALHOU: $(grep -c 'FALHOU' "$OUT/10_administracao_seguranca_testes_v1.txt" || true)"
echo
echo "########## prova de que os testes pegam erro (mutantes) ##########"
echo "Cada linha: uma permissao, papel, policy ou gatilho estragado de proposito, os testes que acusaram FALHOU,"
echo "o veredito final do script (RESULTADO), o script do projeto que desfez o estrago e quantos testes deram OK"
echo "depois (esperado 29). ERROR antes do RESULTADO: o estrago deixou uma acao proibida passar e o efeito dela parou"
echo "o script antes do fim (ja tinha FALHOU antes)."
cat "$OUT/mutantes.txt"
echo
echo "O comando de cada mutante (para repetir a mao: rodar o comando, rodar o 10 com F5, ver o FALHOU e rodar o"
echo "script de conserto da linha acima):"
cat "$OUT/mutantes_sql.txt"
} > "$E/testes_seguranca_v1.txt"

# ---------- os scripts de administracao rodam de novo sem erro (o README diz que pode)
echo "== segunda rodada (07, 08, 09 e 10)"
for f in 07_administracao_views_v1 08_administracao_auditoria_v1 09_administracao_seguranca_v1 10_administracao_seguranca_testes_v1; do
  if docker exec $C sh -c "$P -v ON_ERROR_STOP=1 -f /tmp/final/$f.sql" > "$OUT/${f}_rodada2.txt" 2>&1; then st=ok; else st=ERRO; fi
  echo "$f (2a vez): $st | FALHOU: $(grep -c 'FALHOU' "$OUT/${f}_rodada2.txt" || true) | OK: $(grep -c 'NOTICE:  OK' "$OUT/${f}_rodada2.txt" || true)"
done

echo "== concorrencia no estado final (01 a 11)"
final=$(python -I "$REPO/ferramentas/concorrencia_evidencia.py" "$REPO/sql" /tmp/final "$OUT/concorrencia_estado_final.txt")
echo "$final"
{
echo
echo "==================== a mesma demonstracao depois do 11 (banco completo: gatilhos de log, GIN, papeis e RLS) ===================="
echo "Passos iguais aos de cima, rodados de novo no fim da rodada. Saida completa: so o RESUMO abaixo."
echo "$final"
} >> "$E/concorrencia_duas_abas_v1.txt"
docker exec $C psql -U bd2 -d postgres -q -c "DROP DATABASE IF EXISTS matricula_restaurada WITH (FORCE);"

# ---------- F5 do pgAdmin: cada arquivo inteiro numa mensagem so, no PostgreSQL 16 e no 17
echo "== F5 do pgAdmin (16 e 17)"
{
echo "EVIDENCIAS - CADA SCRIPT RODADO COMO O F5 DO PGADMIN, NO POSTGRESQL 16 E NO 17"
echo "Gerado em $QUANDO. O F5 do Query Tool manda o arquivo inteiro numa mensagem so (pgAdmin 4:"
echo "tools/sqleditor/utils/start_running_query.py chama conn.execute_async(sql) sem parametros, e o psycopg 3 usa"
echo "o protocolo simples, send_query). Aqui cada arquivo vai do mesmo jeito (psql -c com o arquivo inteiro), num"
echo "container novo e vazio para cada versao. 'estado' = o que ficou gravado no banco depois daquele F5."
echo "Os WARNING do 07 e do 08 sao o \"there is no transaction in progress\" do COMMIT explicado nos dois scripts."
echo "A impressao digital do 11 muda de uma versao para a outra (o 17 tem permissoes a mais no catalogo); ela"
echo "compara antes e depois do backup no MESMO servidor."
for img in postgres:16 postgres:17; do
  echo
  IMG=$img SAIDA_DIR="$SP" bash "$REPO/ferramentas/f5_emulacao.sh"
done
} > "$E/rodada_f5_v1.txt"
grep -E '^imagem|exit=[^0]|FALHOU: [^0]|ERROR: [^0]|container removido' "$E/rodada_f5_v1.txt" || true
echo "FIM"
