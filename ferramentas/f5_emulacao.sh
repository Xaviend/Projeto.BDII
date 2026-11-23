#!/usr/bin/env bash
# Emula o F5 do pgAdmin 4: cada arquivo vai inteiro numa mensagem so (psql -c), como o Query Tool faz
# (start_running_query.py -> conn.execute_async(sql) -> psycopg cur.execute(sql) sem parametros -> send_query,
# protocolo simples). Container descartavel bd2_teste_f5 (sem porta publicada), removido no fim.
set -u
export MSYS_NO_PATHCONV=1
# Uso (Git Bash, na pasta do repositorio): IMG=postgres:17 bash ferramentas/f5_emulacao.sh   (padrao: postgres:16)
IMG="${IMG:-postgres:16}"
N="bd2_teste_f5_${IMG##*:}"
SP="${SAIDA_DIR:-${TMPDIR:-/tmp}/bd2_rodada}"
REPO="$(dirname "$(dirname "$(realpath "$0")")")"
OUT="$SP/f5_${IMG##*:}"
rm -rf "$OUT"; mkdir -p "$OUT"

docker rm -f $N >/dev/null 2>&1 || true
docker run -d --name $N -e POSTGRES_USER=bd2 -e POSTGRES_HOST_AUTH_METHOD=trust "$IMG" >/dev/null
echo "imagem: $IMG, versao: $(docker exec $N postgres --version)"
until docker exec $N pg_isready -U bd2 -q 2>/dev/null; do sleep 1; done
sleep 3
until docker exec $N psql -U bd2 -d postgres -Atc "select 1" >/dev/null 2>&1; do sleep 1; done
docker exec $N psql -U bd2 -d postgres -q -c "CREATE DATABASE matricula;"
docker exec $N psql -U bd2 -d matricula -q -c "CREATE SCHEMA academico; CREATE TABLE academico.aluno_prof (id int); INSERT INTO academico.aluno_prof VALUES (1);"
docker exec $N mkdir -p /tmp/f5
for f in "$REPO"/sql/*.sql; do docker cp "$f" $N:/tmp/f5/ >/dev/null; done

q() { docker exec $N psql -U bd2 -d matricula -X -Atc "$1"; }

f5() { # nome_do_arquivo_sem_extensao rotulo
  docker exec $N sh -c 'psql -U bd2 -d matricula -X -c "$(cat /tmp/f5/$1.sql)"' _ "$1" > "$OUT/$2.txt" 2>&1
  st=$?
  printf '%-48s exit=%s | OK: %s | FALHOU: %s | ERROR: %s | WARNING: %s\n' "$2" "$st" \
    "$(grep -c 'NOTICE:  OK' "$OUT/$2.txt")" "$(grep -c 'FALHOU' "$OUT/$2.txt")" \
    "$(grep -c 'ERROR' "$OUT/$2.txt")" "$(grep -c 'WARNING' "$OUT/$2.txt")"
  grep -m3 -E 'ERROR|FALHOU' "$OUT/$2.txt" | sed 's/^/      /'
}

estado() { # o que ficou gravado depois do F5
  echo "   estado: tabelas=$(q "select count(*) from pg_tables where schemaname='projeto_bd2'") \
alunos=$(q "select count(*) from projeto_bd2.tb_aluno" 2>/dev/null || echo -) \
matriculas=$(q "select count(*) from projeto_bd2.tb_matricula" 2>/dev/null || echo -) \
indices=$(q "select count(*) from pg_indexes where schemaname='projeto_bd2'") \
views=$(q "select count(*) from pg_views where schemaname='projeto_bd2'") \
mv=$(q "select count(*) from pg_matviews where schemaname='projeto_bd2'") \
gatilhos=$(q "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='projeto_bd2' and not t.tgisinternal") \
policies=$(q "select count(*) from pg_policies where schemaname='projeto_bd2'") \
papeis=$(q "select count(*) from pg_roles where rolname in ('aluno','secretaria','coordenacao','aluno_26000001','aluno_26000012')") \
log=$(q "select count(*) from projeto_bd2.tb_log_matricula" 2>/dev/null || echo -)"
}

echo "== F5 na ordem do README, banco novo"
f5 01_modelo_fisico_v1 01;                       estado
f5 02_testes_restricoes_v1 02_antes_da_carga;    estado
f5 03_carga_v1 03;                               estado
f5 02_testes_restricoes_v1 02_depois_da_carga;   estado
f5 04_indices_v1 04;                             estado
f5 06_consultas_v1 06;                           estado
f5 07_administracao_views_v1 07;                 estado
f5 08_administracao_auditoria_v1 08;             estado
f5 09_administracao_seguranca_v1 09;             estado
f5 10_administracao_seguranca_testes_v1 10;      estado
f5 11_administracao_backup_conferencia_v1 11;    estado
echo "   impressao digital: $(grep -h 'IMPRESSAO DIGITAL GERAL' "$OUT/11.txt" | tr -s ' ')"
echo "== F5 de novo (07 a 11), para provar que roda mais de uma vez"
f5 07_administracao_views_v1 07_2a;              estado
f5 08_administracao_auditoria_v1 08_2a;          estado
f5 09_administracao_seguranca_v1 09_2a;          estado
f5 10_administracao_seguranca_testes_v1 10_2a;   estado
f5 11_administracao_backup_conferencia_v1 11_2a; estado
echo "== 01 de novo apaga tudo; depois 03, 04, 07, 08, 09 e 10 de novo (o que o README manda)"
for s in 01_modelo_fisico_v1 03_carga_v1 04_indices_v1 07_administracao_views_v1 08_administracao_auditoria_v1 09_administracao_seguranca_v1 10_administracao_seguranca_testes_v1; do
  f5 $s "${s%%_*}_3a"
done
estado
docker rm -f $N >/dev/null
echo "container removido: $(docker ps -a --filter name=$N --format '{{.Names}}' | wc -l) sobrando"
