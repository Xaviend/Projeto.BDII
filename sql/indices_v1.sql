/*
Autor: Iury Xavier Bomfim  - Modelagem Física e Desempenho
Objetivo: criar 4 índices (um deles PARCIAL) e MEDIR o ganho de cada um com EXPLAIN (ANALYZE, BUFFERS) antes e depois.

Como funciona:
  - rodar DEPOIS do modelo_fisico_v1.sql e do carga_v1.sql (sem a carga as tabelas são pequenas demais e o
    PostgreSQL ignora índice, porque ler a tabela inteira sai mais barato);
  - para cada índice o script faz: 1) EXPLAIN ANTES  2) CREATE INDEX  3) EXPLAIN DEPOIS da MESMA consulta;
  - os planos aparecem na aba Messages do pgAdmin (RAISE NOTICE, como no testes_restricoes_v1.sql). O resumo com os
    tempos e os buffers de cada consulta aparece na aba Data Output, no fim. Salvar os dois em evidencias/;
  - pode rodar quantas vezes quiser: no começo ele apaga os 4 índices, então o "antes" é sempre sem índice.

Como ler o EXPLAIN (o que comparar no ANTES e no DEPOIS):
  - tipo de leitura: Seq Scan (lê a tabela inteira) -> Index Scan / Bitmap Index Scan (vai direto nas linhas);
  - Execution Time: tempo real em milissegundos;
  - Buffers: shared hit=N (páginas de 8 kB lidas da memória) + read=N (lidas do disco). Quanto menos páginas, melhor.
    É a medida mais estável: o tempo varia de uma execução para outra, as páginas lidas quase não.

Cada consulta é executada 2 vezes e só a 2ª vai para o resultado: a 1ª serve para "esquentar" o cache. Sem isso o
ANTES pagaria a leitura do disco e o DEPOIS não, e a comparação não seria justa.

indices_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

------------------------------------------------------------------------------------------------------------------------
-- BLOCO 0 - LIMPEZA E AUXILIARES

DROP INDEX IF EXISTS ix_matricula_turma_ativa;
DROP INDEX IF EXISTS ix_historico_situacao_media;
DROP INDEX IF EXISTS ix_matricula_dt;
DROP INDEX IF EXISTS ix_aluno_nm_pattern;

-- Tabela temporária onde cada medição fica guardada para o resumo do fim (some quando a sessão fecha)
DROP TABLE IF EXISTS pg_temp._ganho;
CREATE TEMP TABLE _ganho (consulta TEXT, fase TEXT, ms NUMERIC, buffers INT);

-- Roda EXPLAIN (ANALYZE, BUFFERS) numa consulta, escreve o plano na aba Messages e guarda o tempo e as páginas lidas.
-- Função TEMPORÁRIA (pg_temp): não fica no schema.
CREATE OR REPLACE FUNCTION pg_temp.fn_explain(p_consulta TEXT, p_fase TEXT, p_sql TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_linha    TEXT;
    v_ms       NUMERIC;
    v_buffers  INT;
    v_primeiro BOOLEAN := TRUE;
BEGIN
    -- 1ª execução: só esquenta o cache, o resultado é descartado
    FOR v_linha IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP NULL; END LOOP;

    RAISE NOTICE E'\n=== % - % ===', p_consulta, upper(p_fase);
    FOR v_linha IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        RAISE NOTICE '%', v_linha;
        -- a 1ª linha "Buffers:" do plano é a do nó raiz, que já soma todos os nós de baixo
        IF v_primeiro AND v_linha ~ '^\s*Buffers: shared' THEN
            v_buffers  := COALESCE((regexp_match(v_linha, 'hit=(\d+)'))[1]::int, 0)
                        + COALESCE((regexp_match(v_linha, 'read=(\d+)'))[1]::int, 0);
            v_primeiro := FALSE;
        END IF;
        IF v_linha ~ '^Execution Time:' THEN
            v_ms := (regexp_match(v_linha, 'Execution Time: ([0-9.]+)'))[1]::numeric;
        END IF;
    END LOOP;

    INSERT INTO pg_temp._ganho VALUES (p_consulta, p_fase, v_ms, v_buffers);
END $$;

-- Parâmetro da consulta 1: a turma de Banco de Dados II de 2026/2 (a da "última vaga", criada pela carga)
SELECT set_config('projeto_bd2.turma_alvo',
                  (SELECT t.id_turma::text
                     FROM tb_turma t
                     JOIN tb_disciplina d       ON d.id_disciplina = t.id_disciplina
                     JOIN tb_periodo_letivo p   ON p.id_periodo_letivo = t.id_periodo_letivo
                    WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2
                      AND t.cd_turma = 'A'),
                  false) AS turma_alvo;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - ÍNDICE PARCIAL: matrículas ATIVAS de uma turma
-- Consulta: quantas vagas a turma já ocupou? É a conta que a matrícula faz antes de aceitar um aluno (a "última vaga").
-- Só 'ativa' ocupa vaga; trancada, cancelada e concluida não.
--
-- Por que o ANTES não é um Seq Scan: a UNIQUE (id_aluno, id_turma) já tem um índice, e o PostgreSQL o lê INTEIRO
-- para achar id_turma, porque id_turma é a 2ª coluna dele (um índice só ajuda de verdade na coluna da frente).
--
-- Por que PARCIAL (WHERE ds_status = 'ativa'): só uma fração das linhas é 'ativa', e a consulta só quer essas.
-- O índice guarda só elas: fica bem menor, cabe na memória e custa menos a cada INSERT/UPDATE. A consulta
-- precisa trazer o MESMO filtro (ds_status = 'ativa') para o planejador poder usar o índice.

SELECT pg_temp.fn_explain('1 vagas ocupadas da turma', 'antes',
$q$SELECT count(*) FROM tb_matricula
    WHERE id_turma = current_setting('projeto_bd2.turma_alvo')::int AND ds_status = 'ativa'$q$);

CREATE INDEX ix_matricula_turma_ativa ON tb_matricula (id_turma) WHERE ds_status = 'ativa';

SELECT pg_temp.fn_explain('1 vagas ocupadas da turma', 'depois',
$q$SELECT count(*) FROM tb_matricula
    WHERE id_turma = current_setting('projeto_bd2.turma_alvo')::int AND ds_status = 'ativa'$q$);

-- Quanto o parcial economiza: cria o mesmo índice SEM o WHERE só para comparar o tamanho, e apaga em seguida.
CREATE INDEX ix_tmp_matricula_turma_completo ON tb_matricula (id_turma);
DO $$ BEGIN
    RAISE NOTICE E'\n=== 1 tamanho: parcial x completo ===';
    RAISE NOTICE 'parcial  (so ativas): %', pg_size_pretty(pg_relation_size('ix_matricula_turma_ativa'));
    RAISE NOTICE 'completo (todas)    : %', pg_size_pretty(pg_relation_size('ix_tmp_matricula_turma_completo'));
END $$;
DROP INDEX ix_tmp_matricula_turma_completo;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - ÍNDICE COMPOSTO: ranking de médias
-- Consulta: as 10 maiores médias entre os aprovados (base da função de janela com ranking).
-- Sem índice: lê as ~19 mil linhas aprovadas e ORDENA todas só para devolver 10.
-- Índice (ds_situacao, qt_media_final DESC): a coluna do filtro (=) vem primeiro e a da ordenação depois. As linhas já
-- estão guardadas em ordem decrescente de média, então o PostgreSQL lê só as 10 primeiras e para (LIMIT 10).

SELECT pg_temp.fn_explain('2 top 10 medias dos aprovados', 'antes',
$q$SELECT id_matricula, qt_media_final FROM tb_historico
    WHERE ds_situacao = 'aprovado' ORDER BY qt_media_final DESC LIMIT 10$q$);

CREATE INDEX ix_historico_situacao_media ON tb_historico (ds_situacao, qt_media_final DESC);

SELECT pg_temp.fn_explain('2 top 10 medias dos aprovados', 'depois',
$q$SELECT id_matricula, qt_media_final FROM tb_historico
    WHERE ds_situacao = 'aprovado' ORDER BY qt_media_final DESC LIMIT 10$q$);


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 3 - ÍNDICE PARA ORDENAÇÃO: últimas matrículas realizadas
-- Consulta: as 20 matrículas mais recentes (tela da secretaria).
-- Sem índice: lê as ~25 mil matrículas e ordena todas por data. Com índice em dt_matricula o PostgreSQL percorre o
-- índice de trás para frente (Index Scan Backward) e para na 20ª linha: não precisa de DESC no índice.

SELECT pg_temp.fn_explain('3 ultimas 20 matriculas', 'antes',
$q$SELECT id_matricula, id_aluno, dt_matricula FROM tb_matricula
    ORDER BY dt_matricula DESC LIMIT 20$q$);

CREATE INDEX ix_matricula_dt ON tb_matricula (dt_matricula);

SELECT pg_temp.fn_explain('3 ultimas 20 matriculas', 'depois',
$q$SELECT id_matricula, id_aluno, dt_matricula FROM tb_matricula
    ORDER BY dt_matricula DESC LIMIT 20$q$);


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 4 - ÍNDICE PARA BUSCA POR PREFIXO: aluno pelo começo do nome
-- Consulta: LIKE 'Ana Silva%' (a secretaria digita o começo do nome).
-- Um índice comum NÃO atende LIKE quando o banco usa uma collation de idioma (como pt_BR ou en_US): a ordem dos
-- textos nela não é a ordem dos caracteres. A classe de operador varchar_pattern_ops compara caractere a caractere
-- e serve para LIKE 'texto%'. Ela NÃO serve para '%texto' nem '%texto%' (começo coringa): esses precisariam de
-- pg_trgm, que não usamos.

SELECT pg_temp.fn_explain('4 aluno pelo prefixo do nome', 'antes',
$q$SELECT id_aluno, nm_aluno FROM tb_aluno WHERE nm_aluno LIKE 'Ana Silva%'$q$);

CREATE INDEX ix_aluno_nm_pattern ON tb_aluno (nm_aluno varchar_pattern_ops);

SELECT pg_temp.fn_explain('4 aluno pelo prefixo do nome', 'depois',
$q$SELECT id_aluno, nm_aluno FROM tb_aluno WHERE nm_aluno LIKE 'Ana Silva%'$q$);


------------------------------------------------------------------------------------------------------------------------
-- TAMANHO DOS ÍNDICES CRIADOS (aba Messages)
DO $$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE E'\n=== tamanho dos indices criados ===';
    FOR r IN SELECT indexname, pg_size_pretty(pg_relation_size(('projeto_bd2.' || indexname)::regclass)) AS tamanho
               FROM pg_indexes
              WHERE schemaname = 'projeto_bd2' AND indexname LIKE 'ix\_%'
              ORDER BY indexname
    LOOP
        RAISE NOTICE '% : %', rpad(r.indexname, 30), r.tamanho;
    END LOOP;
END $$;

------------------------------------------------------------------------------------------------------------------------
--RESUMO ANTES x DEPOIS (aba Data Output)
-- ms = Execution Time em milissegundos | buffers = páginas de 8 kB lidas (hit + read)
-- O tempo muda um pouco a cada execução; as páginas lidas quase não mudam.
SELECT a.consulta,
       a.ms                                    AS ms_antes,
       d.ms                                    AS ms_depois,
       round(a.ms / NULLIF(d.ms, 0), 1)        AS vezes_mais_rapido,
       a.buffers                               AS buffers_antes,
       d.buffers                               AS buffers_depois
  FROM pg_temp._ganho a
  JOIN pg_temp._ganho d ON d.consulta = a.consulta AND d.fase = 'depois'
 WHERE a.fase = 'antes'
 ORDER BY a.consulta;
