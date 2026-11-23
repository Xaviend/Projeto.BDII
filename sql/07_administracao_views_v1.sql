/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: criar as 3 views do Marco 2 (oferta, vagas e histórico) e 1 materialized view de indicadores, com a
          política de atualização justificada e o ganho da materialized view medido com EXPLAIN (ANALYZE, BUFFERS).

Como rodar:
  - rodar DEPOIS do 01_modelo_fisico_v1.sql, do 03_carga_v1.sql e do 04_indices_v1.sql;
  - pode rodar quantas vezes quiser (CREATE OR REPLACE nas views, DROP ... IF EXISTS na materialized view);
  - o 09_administracao_seguranca_v1.sql roda DEPOIS deste: é ele que dá acesso às views para cada papel.
  Roda inteiro com F5. Os planos aparecem na aba Messages e o resumo antes x depois na aba Data Output.

VIEW x MATERIALIZED VIEW
  - VIEW guarda só a CONSULTA. Cada SELECT na view roda a consulta de novo: o dado está sempre atual.
    O planejador "abre" a view e otimiza tudo junto, então ela usa os mesmos índices das tabelas.
  - MATERIALIZED VIEW guarda o RESULTADO em disco. A leitura é rápida, mas o dado fica congelado até o REFRESH.

security_invoker (PostgreSQL 15 em diante)
  - Por padrão a view lê as tabelas com as permissões do DONO da view. Aqui o dono é o bd2, que é superusuário e
    ignora o RLS. Ou seja: sem cuidado, um aluno consultando a view veria o histórico de todo mundo.
  - Com security_invoker = true a view usa as permissões de QUEM CONSULTA, e o RLS do aluno vale dentro dela.
  - vw_oferta e vw_historico usam security_invoker = true. A vw_vagas NÃO usa, de propósito (ver bloco 2).

07_administracao_views_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - vw_oferta: a oferta de turmas (o que o aluno escolhe na hora de se matricular)
-- Uma linha por turma, com os horários juntos numa coluna só (string_agg).
-- GROUP BY pela chave primária: o PostgreSQL sabe que as outras colunas da mesma tabela dependem dela
-- (dependência funcional), então não precisa repetir todas no GROUP BY.
-- LEFT JOIN no horário: turma ainda sem horário cadastrado continua aparecendo na oferta.

-- ic_periodo_atual: semestre atual = o período letivo mais recente cadastrado (mesma regra do 06_consultas_v1.sql),
-- e não a data de hoje. Pela data, depois do fim do 2026/2 (11/12) nenhum semestre seria o atual e a oferta sumiria.
CREATE OR REPLACE VIEW vw_oferta
WITH (security_invoker = true) AS
SELECT t.id_turma,
       p.aa_periodo || '/' || p.cd_semestre                          AS ds_periodo,
       (p.id_periodo_letivo = (SELECT pa.id_periodo_letivo FROM tb_periodo_letivo pa
                                ORDER BY pa.aa_periodo DESC, pa.cd_semestre DESC
                                LIMIT 1))                            AS ic_periodo_atual,
       d.cd_disciplina,
       d.nm_disciplina,
       d.qt_ch_total,
       t.cd_turma,
       t.ds_turno,
       pr.nm_professor,
       string_agg((ARRAY['seg','ter','qua','qui','sex','sab','dom'])[h.dd_semana]
                  || ' ' || to_char(h.hr_inicio, 'HH24:MI') || '-' || to_char(h.hr_fim, 'HH24:MI')
                  || ' sala ' || s.cd_sala,
                  ', ' ORDER BY h.dd_semana, h.hr_inicio)             AS ds_horarios,
       t.qt_vagas
  FROM tb_turma t
  JOIN tb_disciplina d         ON d.id_disciplina = t.id_disciplina
  JOIN tb_periodo_letivo p     ON p.id_periodo_letivo = t.id_periodo_letivo
  JOIN tb_professor pr         ON pr.id_professor = t.id_professor
  LEFT JOIN tb_turma_horario h ON h.id_turma = t.id_turma
  LEFT JOIN tb_sala s          ON s.id_sala = h.id_sala
 GROUP BY t.id_turma, p.id_periodo_letivo, d.id_disciplina, pr.id_professor;

-- Teste: a oferta de Banco de Dados II no semestre atual
SELECT ds_periodo, cd_disciplina, cd_turma, ds_turno, nm_professor, ds_horarios, qt_vagas
  FROM vw_oferta
 WHERE ic_periodo_atual AND cd_disciplina = 'CCO072'
 ORDER BY cd_turma;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - vw_vagas: ocupação de cada turma (vagas, ocupadas, livres)
-- Só matrícula 'ativa' ocupa vaga (trancada, cancelada e concluida não).
--
-- ATENÇÃO ao LEFT JOIN: o filtro ds_status = 'ativa' fica no ON, e não no WHERE. No WHERE ele jogaria fora as
-- turmas sem nenhuma matrícula (o m.ds_status seria NULL) e o LEFT JOIN viraria um INNER JOIN.
-- count(m.id_matricula) e não count(*): na turma vazia o LEFT JOIN cria uma linha com m.id_matricula NULL, e
-- count(*) contaria essa linha como 1.
--
-- Por que esta view NÃO tem security_invoker:
--   o número de vagas ocupadas precisa contar as matrículas de TODOS os alunos. Se a view usasse as permissões de
--   quem consulta, o RLS do aluno deixaria ele contar só a própria matrícula e a turma pareceria vazia.
--   Ela roda com as permissões do dono e devolve só NÚMEROS (nenhum nome, nenhuma nota): o aluno vê quantas vagas
--   sobram sem ver quem está matriculado. É uma forma comum de expor um dado agregado sem expor as linhas.

CREATE OR REPLACE VIEW vw_vagas
WITH (security_invoker = false) AS
SELECT t.id_turma,
       p.aa_periodo || '/' || p.cd_semestre                          AS ds_periodo,
       (p.id_periodo_letivo = (SELECT pa.id_periodo_letivo FROM tb_periodo_letivo pa
                                ORDER BY pa.aa_periodo DESC, pa.cd_semestre DESC
                                LIMIT 1))                            AS ic_periodo_atual,   -- mesma regra da vw_oferta
       d.cd_disciplina,
       d.nm_disciplina,
       t.cd_turma,
       t.qt_vagas,
       count(m.id_matricula)                                         AS qt_ocupadas,
       t.qt_vagas - count(m.id_matricula)                            AS qt_livres,
       round(100.0 * count(m.id_matricula) / t.qt_vagas, 1)          AS pc_ocupacao,
       CASE WHEN count(m.id_matricula) >= t.qt_vagas     THEN 'lotada'
            WHEN t.qt_vagas - count(m.id_matricula) <= 5 THEN 'ultimas vagas'
            ELSE 'com vagas' END                                      AS ds_situacao_vagas
  FROM tb_turma t
  JOIN tb_disciplina d      ON d.id_disciplina = t.id_disciplina
  JOIN tb_periodo_letivo p  ON p.id_periodo_letivo = t.id_periodo_letivo
  LEFT JOIN tb_matricula m  ON m.id_turma = t.id_turma
                           AND m.ds_status = 'ativa'               -- no ON, não no WHERE
 GROUP BY t.id_turma, p.id_periodo_letivo, d.id_disciplina;

-- Teste: a turma da "última vaga" (CCO072, 2026/2, A) tem que mostrar qt_livres = 1
SELECT ds_periodo, cd_disciplina, cd_turma, qt_vagas, qt_ocupadas, qt_livres, pc_ocupacao, ds_situacao_vagas
  FROM vw_vagas
 WHERE ic_periodo_atual AND cd_disciplina = 'CCO072'
 ORDER BY cd_turma;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 3 - vw_historico: o histórico escolar (notas, frequência, média e situação de cada disciplina cursada)
-- security_invoker = true: com o RLS do 09_administracao_seguranca_v1.sql, o aluno que consulta esta view só recebe
-- as PRÓPRIAS linhas; a secretaria e a coordenação recebem todas. A regra fica nas tabelas, não na view:
-- quem tentar ler tb_historico direto esbarra no mesmo RLS.
-- Só entram matrículas que têm histórico (trancada e cancelada não têm: é o (0,1) do modelo).

CREATE OR REPLACE VIEW vw_historico
WITH (security_invoker = true) AS
SELECT a.id_aluno,
       a.cd_matricula,
       a.nm_aluno,
       c.cd_curso,
       p.aa_periodo,
       p.cd_semestre,
       p.aa_periodo || '/' || p.cd_semestre   AS ds_periodo,
       d.cd_disciplina,
       d.nm_disciplina,
       d.qt_ch_total,
       t.cd_turma,
       m.ds_status,
       h.qt_nota_a1,
       h.qt_nota_a2,
       h.qt_nota_p3,
       h.qt_media_final,
       h.pc_frequencia,
       h.ds_situacao
  FROM tb_historico h
  JOIN tb_matricula m      ON m.id_matricula = h.id_matricula
  JOIN tb_aluno a          ON a.id_aluno = m.id_aluno
  JOIN tb_curso c          ON c.id_curso = a.id_curso
  JOIN tb_turma t          ON t.id_turma = m.id_turma
  JOIN tb_disciplina d     ON d.id_disciplina = t.id_disciplina
  JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo;

-- Teste: o histórico de um aluno do 8º semestre (aqui, como bd2, a view mostra tudo; com RLS o aluno vê só o dele)
SELECT ds_periodo, cd_disciplina, nm_disciplina, qt_nota_a1, qt_nota_a2, qt_nota_p3, qt_media_final,
       pc_frequencia, ds_situacao
  FROM vw_historico
 WHERE cd_matricula = '26000012'
 ORDER BY aa_periodo, cd_semestre, cd_disciplina;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 4 - mv_indicadores: indicadores de desempenho por curso e semestre (painel da coordenação)
--
-- POLÍTICA DE ATUALIZAÇÃO (e o porquê):
--   1. O que ela mostra (aprovação, reprovação, média e frequência por curso e semestre) só muda quando a
--      secretaria lança nota, o que acontece em poucas janelas do semestre (A1, A2, P3). Fora delas o dado não muda.
--   2. A consulta por trás junta 6 tabelas e agrega ~25 mil históricos; o painel é aberto muitas vezes por dia.
--      Recalcular a cada abertura é desperdício: grava-se o resultado uma vez e lê-se muitas.
--   3. A coordenação aceita ver o número de ontem: indicador de desempenho não é dado de tempo real.
--   Por isso: REFRESH logo depois de cada lançamento de notas e uma vez por noite, sempre chamando
--   fn_atualizar_indicadores(). O agendamento da noite fica fora do banco: o ambiente da disciplina não tem o
--   pg_cron, então em produção seria um job do servidor (cron) rodando "SELECT projeto_bd2.fn_atualizar_indicadores();".
--   Neste projeto o REFRESH é chamado à mão (BLOCO 5).
--   O REFRESH é CONCURRENTLY: quem está lendo o painel não fica travado durante a atualização. O preço é que
--   ele exige um índice ÚNICO na materialized view e é mais lento que o REFRESH comum (compara o novo resultado
--   com o antigo e só troca as linhas que mudaram).
--   Não usamos gatilho (trigger) para atualizar a cada nota lançada: cada INSERT/UPDATE em tb_historico
--   recalcularia o painel inteiro, e o lançamento de uma turma de 45 alunos faria 45 recálculos.
--
-- dt_atualizacao = now() no momento do REFRESH: o painel mostra de quando é o número.
-- Materialized view NÃO tem RLS. Por isso ela só guarda totais (nenhum aluno aparece) e só a equipe tem acesso.

DROP MATERIALIZED VIEW IF EXISTS mv_indicadores;
CREATE MATERIALIZED VIEW mv_indicadores AS
SELECT c.id_curso,
       c.cd_curso,
       p.id_periodo_letivo,
       p.aa_periodo,
       p.cd_semestre,
       p.aa_periodo || '/' || p.cd_semestre                                       AS ds_periodo,
       count(DISTINCT m.id_aluno)                                                 AS qt_alunos,
       count(*)                                                                   AS qt_historicos,
       count(*) FILTER (WHERE h.ds_situacao = 'aprovado')                         AS qt_aprovados,
       count(*) FILTER (WHERE h.ds_situacao = 'reprovado_nota')                   AS qt_reprovados_nota,
       count(*) FILTER (WHERE h.ds_situacao = 'reprovado_falta')                  AS qt_reprovados_falta,
       count(*) FILTER (WHERE h.ds_situacao = 'cursando')                         AS qt_cursando,
       -- taxa de aprovação sobre quem já terminou a disciplina (cursando fica de fora da conta)
       round(100.0 * count(*) FILTER (WHERE h.ds_situacao = 'aprovado')
             / NULLIF(count(*) FILTER (WHERE h.ds_situacao <> 'cursando'), 0), 1)  AS pc_aprovacao,
       round(avg(h.qt_media_final), 2)                                            AS qt_media_geral,
       round(avg(h.pc_frequencia), 1)                                             AS pc_frequencia_media,
       now()                                                                      AS dt_atualizacao
  FROM tb_historico h
  JOIN tb_matricula m      ON m.id_matricula = h.id_matricula
  JOIN tb_aluno a          ON a.id_aluno = m.id_aluno
  JOIN tb_curso c          ON c.id_curso = a.id_curso
  JOIN tb_turma t          ON t.id_turma = m.id_turma
  JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
 GROUP BY c.id_curso, p.id_periodo_letivo;

-- Índice ÚNICO: obrigatório para o REFRESH ... CONCURRENTLY (é por ele que o PostgreSQL acha a linha que mudou)
CREATE UNIQUE INDEX uq_mv_indicadores ON mv_indicadores (id_curso, id_periodo_letivo);

-- Quem atualiza o painel: só o DONO da materialized view pode dar REFRESH. Em vez de dar a posse à coordenação,
-- a função abaixo roda com os direitos do dono (SECURITY DEFINER) e a coordenação recebe só o EXECUTE dela.
-- SET search_path fixo: sem ele, quem chama poderia criar um objeto com o mesmo nome em outro schema e
-- enganar uma função que roda com direitos de dono.
CREATE OR REPLACE FUNCTION fn_atualizar_indicadores() RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = projeto_bd2, pg_temp
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores;
    RETURN (SELECT max(dt_atualizacao) FROM mv_indicadores);
END $$;

-- Toda função nasce com EXECUTE liberado para PUBLIC (todo mundo). Esta não pode: fecha aqui, e o
-- 09_administracao_seguranca_v1.sql libera só para a coordenação.
REVOKE ALL ON FUNCTION fn_atualizar_indicadores() FROM PUBLIC;

-- Teste: o painel de Ciência da Computação, semestre a semestre
SELECT ds_periodo, qt_alunos, qt_historicos, qt_aprovados, qt_reprovados_nota, qt_reprovados_falta, qt_cursando,
       pc_aprovacao, qt_media_geral, pc_frequencia_media
  FROM mv_indicadores
 WHERE cd_curso = 'CCO'
 ORDER BY aa_periodo, cd_semestre;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 5 - A PROVA DE QUE A MATERIALIZED VIEW FICA "CONGELADA" ATÉ O REFRESH
-- Roda dentro de BEGIN ... ROLLBACK: no fim, nada fica gravado.
-- Simula o lançamento da A2 de um aluno de CCO em 2026/2: ele passa de 'cursando' para 'aprovado'.
-- COMMIT antes do BEGIN: o F5 manda o arquivo inteiro de uma vez, e aí o PostgreSQL trata tudo como UMA transação.
-- Sem este COMMIT, o ROLLBACK do fim do bloco desfaria também as views e a materialized view criadas acima.
-- Rodando passo a passo, o COMMIT só avisa "there is no transaction in progress" (WARNING inofensivo).

COMMIT;
BEGIN;

UPDATE tb_historico h
   SET qt_nota_a2 = 9.0, ds_situacao = 'aprovado'
 WHERE h.id_historico = (
        SELECT h2.id_historico
          FROM tb_historico h2
          JOIN tb_matricula m      ON m.id_matricula = h2.id_matricula
          JOIN tb_aluno a          ON a.id_aluno = m.id_aluno
          JOIN tb_curso c          ON c.id_curso = a.id_curso AND c.cd_curso = 'CCO'
          JOIN tb_turma t          ON t.id_turma = m.id_turma
          JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
                                  AND p.aa_periodo = 2026 AND p.cd_semestre = 2
         WHERE h2.ds_situacao = 'cursando' AND h2.pc_frequencia >= 75 AND h2.qt_nota_a1 >= 5
         ORDER BY h2.id_historico
         LIMIT 1);

-- ANTES do REFRESH: a tabela já conta o aprovado novo; a materialized view ainda não
SELECT 'antes do refresh' AS momento,
       (SELECT count(*) FROM vw_historico
         WHERE cd_curso = 'CCO' AND ds_periodo = '2026/2' AND ds_situacao = 'aprovado')      AS aprovados_na_tabela,
       (SELECT qt_aprovados FROM mv_indicadores WHERE cd_curso = 'CCO' AND ds_periodo = '2026/2') AS aprovados_na_mv;

SELECT fn_atualizar_indicadores() AS atualizado_em;

-- DEPOIS do REFRESH: as duas fontes batem
SELECT 'depois do refresh' AS momento,
       (SELECT count(*) FROM vw_historico
         WHERE cd_curso = 'CCO' AND ds_periodo = '2026/2' AND ds_situacao = 'aprovado')      AS aprovados_na_tabela,
       (SELECT qt_aprovados FROM mv_indicadores WHERE cd_curso = 'CCO' AND ds_periodo = '2026/2') AS aprovados_na_mv;

ROLLBACK;   -- desfaz a nota e o REFRESH: o banco volta como estava


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 6 - GANHO MEDIDO: a consulta dos indicadores calculada na hora x lida da materialized view
-- Mesmo método do 04_indices_v1.sql: EXPLAIN (ANALYZE, BUFFERS) duas vezes, só a 2ª conta (a 1ª esquenta o cache).
-- Mede também a vw_vagas de UMA turma, para mostrar que a view usa o índice parcial ix_matricula_turma_ativa
-- do 04_indices_v1.sql (a view não tem plano próprio: o planejador abre a consulta dela).

DROP TABLE IF EXISTS pg_temp._ganho_adm;
CREATE TEMP TABLE _ganho_adm (consulta TEXT, fase TEXT, ms NUMERIC, buffers INT);

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
    INSERT INTO pg_temp._ganho_adm VALUES (p_consulta, p_fase, v_ms, v_buffers);
END $$;

-- 1) indicadores de CCO calculados na hora (a mesma consulta da materialized view, filtrada)
SELECT pg_temp.fn_medir('1 indicadores de CCO', 'na hora (sem mv)',
$q$SELECT p.aa_periodo, p.cd_semestre,
          count(DISTINCT m.id_aluno),
          count(*) FILTER (WHERE h.ds_situacao = 'aprovado'),
          round(avg(h.qt_media_final), 2),
          round(avg(h.pc_frequencia), 1)
     FROM tb_historico h
     JOIN tb_matricula m      ON m.id_matricula = h.id_matricula
     JOIN tb_aluno a          ON a.id_aluno = m.id_aluno
     JOIN tb_curso c          ON c.id_curso = a.id_curso
     JOIN tb_turma t          ON t.id_turma = m.id_turma
     JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
    WHERE c.cd_curso = 'CCO'
    GROUP BY p.aa_periodo, p.cd_semestre$q$);

-- 2) os mesmos indicadores lidos da materialized view
SELECT pg_temp.fn_medir('1 indicadores de CCO', 'lido da mv',
$q$SELECT aa_periodo, cd_semestre, qt_alunos, qt_aprovados, qt_media_geral, pc_frequencia_media
     FROM mv_indicadores
    WHERE cd_curso = 'CCO'$q$);

-- 3) vagas de UMA turma pela view: o plano mostra o índice parcial do 04_indices_v1.sql sendo usado
SELECT pg_temp.fn_medir('2 vagas de uma turma pela vw_vagas', 'view',
$q$SELECT qt_vagas, qt_ocupadas, qt_livres
     FROM vw_vagas
    WHERE id_turma = (SELECT t.id_turma
                        FROM tb_turma t
                        JOIN tb_disciplina d     ON d.id_disciplina = t.id_disciplina AND d.cd_disciplina = 'CCO072'
                        JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
                                                AND p.aa_periodo = 2026 AND p.cd_semestre = 2
                       WHERE t.cd_turma = 'A')$q$);

------------------------------------------------------------------------------------------------------------------------
-- RESUMO (aba Data Output)
-- ms = Execution Time em milissegundos | buffers = páginas de 8 kB lidas (hit + read)
SELECT a.consulta,
       a.fase                                  AS fase_1,
       a.ms                                    AS ms_1,
       a.buffers                               AS buffers_1,
       b.fase                                  AS fase_2,
       b.ms                                    AS ms_2,
       b.buffers                               AS buffers_2,
       round(a.ms / NULLIF(b.ms, 0), 1)        AS vezes_mais_rapido
  FROM pg_temp._ganho_adm a
  LEFT JOIN pg_temp._ganho_adm b ON b.consulta = a.consulta AND b.fase = 'lido da mv'
 WHERE a.fase <> 'lido da mv'
 ORDER BY a.consulta;
