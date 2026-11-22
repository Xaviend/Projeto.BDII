/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: (1) auditoria automática das matrículas e das notas: um gatilho (trigger) grava em tb_log_matricula cada
              INSERT, UPDATE e DELETE feito em tb_matricula e em tb_historico, com a linha ANTES e DEPOIS em JSONB.
              Só o gatilho grava no log: INSERT feito direto na tabela é recusado (ninguém inventa linha de log);
          (2) BÔNUS do Marco 2 (JSONB com índice GIN): índice GIN na coluna ds_detalhe do log, com o ganho medido
              por EXPLAIN (ANALYZE, BUFFERS) antes e depois.

Como rodar:
  - rodar DEPOIS do 07_administracao_views_v1.sql e ANTES do 09_administracao_seguranca_v1.sql (o de segurança fecha
    as permissões de tudo que existe, inclusive da função deste gatilho);
  - pode rodar quantas vezes quiser (DROP ... IF EXISTS e a carga inicial do log não duplica linhas).
  Roda inteiro com F5. Os planos aparecem na aba Messages e o resumo na aba Data Output.

Por que JSONB:
  o log guarda a linha inteira de antes e de depois. Se tb_matricula ganhar uma coluna amanhã, o log continua
  funcionando sem ALTER TABLE: a coluna nova simplesmente aparece dentro do JSON.
  JSONB (e não JSON): é guardado já "desmontado" em formato binário, aceita índice e os operadores @>, ->, ->>.

08_administracao_auditoria_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - GATILHO DE AUDITORIA
-- AFTER ... FOR EACH ROW: roda depois de cada linha alterada, quando a mudança já passou por todas as restrições.
-- Se a transação da matrícula der ROLLBACK, o registro do log some junto: o log nunca mostra o que não aconteceu.
-- O mesmo gatilho vigia tb_matricula e tb_historico (as notas): as duas têm id_matricula, e "tabela" no JSON diz
-- de qual veio a mudança.
-- nm_usuario e dt_ocorrencia vêm do DEFAULT da tabela (CURRENT_USER e CURRENT_TIMESTAMP).
-- A função roda com as permissões de quem alterou a matrícula (não é SECURITY DEFINER): é assim que o
-- CURRENT_USER do log mostra quem fez. Por isso a secretaria recebe INSERT no log (e só INSERT: ninguém além do
-- dono edita ou apaga o log), ver 09_administracao_seguranca_v1.sql.
-- usuario_sessao: o usuário que conectou no banco. Se a funcionária maria conecta e faz SET ROLE secretaria, o
-- nm_usuario grava "secretaria" e o usuario_sessao grava "maria": o log diz o papel e a pessoa.
-- SET search_path: o gatilho acha tb_log_matricula mesmo quando quem alterou a matrícula não fez
-- "SET search_path TO projeto_bd2" antes (sem isso o UPDATE falha com "relation tb_log_matricula does not exist").

CREATE OR REPLACE FUNCTION fn_log_matricula() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = projeto_bd2, pg_temp AS $$
BEGIN
    -- No INSERT o OLD é NULL; no DELETE o NEW é NULL. to_jsonb(NULL) vira null no JSON.
    INSERT INTO tb_log_matricula (id_matricula, ds_acao, ds_detalhe)
    VALUES (COALESCE(NEW.id_matricula, OLD.id_matricula),
            TG_OP,                                              -- 'INSERT', 'UPDATE' ou 'DELETE'
            jsonb_build_object('tabela', TG_TABLE_NAME, 'antes', to_jsonb(OLD), 'depois', to_jsonb(NEW),
                               'usuario_sessao', session_user));
    RETURN NULL;                                                -- num gatilho AFTER o retorno é ignorado
END $$;

DROP TRIGGER IF EXISTS trg_log_matricula ON tb_matricula;
CREATE TRIGGER trg_log_matricula
    AFTER INSERT OR UPDATE OR DELETE ON tb_matricula
    FOR EACH ROW EXECUTE FUNCTION fn_log_matricula();

DROP TRIGGER IF EXISTS trg_log_historico ON tb_historico;
CREATE TRIGGER trg_log_historico
    AFTER INSERT OR UPDATE OR DELETE ON tb_historico
    FOR EACH ROW EXECUTE FUNCTION fn_log_matricula();

-- Só o gatilho grava no log. A secretaria precisa de INSERT no log (o gatilho roda com o usuário dela), e sem esta
-- trava ela poderia fazer um INSERT direto com um "antes" e "depois" inventados.
-- pg_trigger_depth() = quantos gatilhos estão rodando um dentro do outro. Linha vinda do trg_log_matricula chega
-- aqui com 2 (aquele gatilho + este); INSERT direto chega com 1 e é recusado.
-- Superusuário passa (a carga inicial do BLOCO 2 é dele, e superusuário poderia apagar esta trava de qualquer jeito).
CREATE OR REPLACE FUNCTION fn_log_so_pelo_gatilho() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = projeto_bd2, pg_temp AS $$
BEGIN
    IF pg_trigger_depth() < 2 AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'tb_log_matricula so recebe linha do gatilho de auditoria (usuario %)', current_user
              USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_log_so_pelo_gatilho ON tb_log_matricula;
CREATE TRIGGER trg_log_so_pelo_gatilho
    BEFORE INSERT ON tb_log_matricula
    FOR EACH ROW EXECUTE FUNCTION fn_log_so_pelo_gatilho();

-- Teste do gatilho (BEGIN ... ROLLBACK: nada fica gravado): tranca uma matrícula ativa e confere o log
BEGIN;
UPDATE tb_matricula SET ds_status = 'trancada'
 WHERE id_matricula = (SELECT min(id_matricula) FROM tb_matricula WHERE ds_status = 'ativa');
SELECT id_matricula, ds_acao, nm_usuario,
       ds_detalhe -> 'antes'  ->> 'ds_status' AS status_antes,
       ds_detalhe -> 'depois' ->> 'ds_status' AS status_depois
  FROM tb_log_matricula
 ORDER BY id_log_matricula DESC
 LIMIT 1;
ROLLBACK;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - CARGA INICIAL DO LOG
-- O gatilho só registra o que acontece DEPOIS de criado. As ~25 mil matrículas da 03_carga_v1.sql nasceram antes dele,
-- então o log não tinha a criação delas. Aqui o log recebe o INSERT de cada matrícula que ainda não tem, no mesmo
-- formato que o gatilho grava, com a data em que a matrícula foi feita.
-- NOT EXISTS: rodar de novo não duplica nada.

INSERT INTO tb_log_matricula (id_matricula, ds_acao, dt_ocorrencia, nm_usuario, ds_detalhe)
SELECT m.id_matricula, 'INSERT', m.dt_matricula, 'carga_inicial',
       jsonb_build_object('tabela', 'tb_matricula', 'antes', NULL, 'depois', to_jsonb(m))
  FROM tb_matricula m
 WHERE NOT EXISTS (SELECT 1 FROM tb_log_matricula l
                    WHERE l.id_matricula = m.id_matricula AND l.ds_acao = 'INSERT');

ANALYZE tb_log_matricula;

SELECT ds_acao, nm_usuario, count(*) AS linhas
  FROM tb_log_matricula
 GROUP BY ds_acao, nm_usuario
 ORDER BY ds_acao, nm_usuario;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 3 - BÔNUS: ÍNDICE GIN NO JSONB
-- Consulta: "toda a movimentação de um aluno no log" (a secretaria responde uma reclamação de matrícula).
-- O id do aluno está DENTRO do JSON: ds_detalhe @> '{"depois": {"id_aluno": N}}' quer dizer
-- "o JSON contém este pedaço". Um índice B-tree comum não enxerga dentro do JSON; o GIN indexa cada chave e valor.
-- jsonb_path_ops: versão do GIN que só atende o @> (o único operador que usamos), mas fica menor e mais rápida que a
-- padrão (jsonb_ops, que atende também ?, ?| e ?&).

DROP INDEX IF EXISTS ix_log_matricula_detalhe;

DROP TABLE IF EXISTS pg_temp._ganho_gin;
CREATE TEMP TABLE _ganho_gin (consulta TEXT, fase TEXT, ms NUMERIC, buffers INT);

CREATE OR REPLACE FUNCTION pg_temp.fn_medir(p_consulta TEXT, p_fase TEXT, p_sql TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_linha    TEXT;
    v_ms       NUMERIC;
    v_buffers  INT;
    v_primeiro BOOLEAN := TRUE;
BEGIN
    FOR v_linha IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP NULL; END LOOP;   -- esquenta o cache

    RAISE NOTICE E'\n=== % - % ===', p_consulta, upper(p_fase);
    FOR v_linha IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        RAISE NOTICE '%', v_linha;
        IF v_primeiro AND v_linha ~ '^\s*Buffers: shared' THEN          -- 1ª linha Buffers = total do nó raiz
            v_buffers  := COALESCE((regexp_match(v_linha, 'hit=(\d+)'))[1]::int, 0)
                        + COALESCE((regexp_match(v_linha, 'read=(\d+)'))[1]::int, 0);
            v_primeiro := FALSE;
        END IF;
        IF v_linha ~ '^Execution Time:' THEN
            v_ms := (regexp_match(v_linha, 'Execution Time: ([0-9.]+)'))[1]::numeric;
        END IF;
    END LOOP;
    INSERT INTO pg_temp._ganho_gin VALUES (p_consulta, p_fase, v_ms, v_buffers);
END $$;

-- O aluno 26000012 (8º semestre de CCO, 22 matrículas)
SELECT set_config('projeto_bd2.aluno_alvo',
                  (SELECT id_aluno::text FROM tb_aluno WHERE cd_matricula = '26000012'), false) AS aluno_alvo;

SELECT pg_temp.fn_medir('5 log de um aluno (JSONB @>)', 'antes',
$q$SELECT id_log_matricula, ds_acao, dt_ocorrencia
     FROM tb_log_matricula
    WHERE ds_detalhe @> jsonb_build_object('depois',
                         jsonb_build_object('id_aluno', current_setting('projeto_bd2.aluno_alvo')::int))$q$);

CREATE INDEX ix_log_matricula_detalhe ON tb_log_matricula USING gin (ds_detalhe jsonb_path_ops);

SELECT pg_temp.fn_medir('5 log de um aluno (JSONB @>)', 'depois',
$q$SELECT id_log_matricula, ds_acao, dt_ocorrencia
     FROM tb_log_matricula
    WHERE ds_detalhe @> jsonb_build_object('depois',
                         jsonb_build_object('id_aluno', current_setting('projeto_bd2.aluno_alvo')::int))$q$);

DO $$ BEGIN
    RAISE NOTICE E'\n=== tamanho do indice GIN ===';
    RAISE NOTICE 'ix_log_matricula_detalhe: %', pg_size_pretty(pg_relation_size('ix_log_matricula_detalhe'));
    RAISE NOTICE 'tb_log_matricula        : %', pg_size_pretty(pg_relation_size('tb_log_matricula'));
END $$;

------------------------------------------------------------------------------------------------------------------------
-- RESUMO ANTES x DEPOIS (aba Data Output)
-- ms = Execution Time em milissegundos | buffers = páginas de 8 kB lidas (hit + read)
SELECT a.consulta,
       a.ms                                    AS ms_antes,
       d.ms                                    AS ms_depois,
       round(a.ms / NULLIF(d.ms, 0), 1)        AS vezes_mais_rapido,
       a.buffers                               AS buffers_antes,
       d.buffers                               AS buffers_depois
  FROM pg_temp._ganho_gin a
  JOIN pg_temp._ganho_gin d ON d.consulta = a.consulta AND d.fase = 'depois'
 WHERE a.fase = 'antes';
