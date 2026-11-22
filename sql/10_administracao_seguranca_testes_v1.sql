/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: provar que os papéis, os GRANT/REVOKE, o RLS e a trava do log (09_administracao_seguranca_v1.sql e
          08_administracao_auditoria_v1.sql) funcionam. Cada teste troca de papel com SET ROLE e confere o resultado:
            - o que DEVE funcionar funciona (teste positivo) e
            - o que DEVE ser barrado é barrado (teste negativo), sempre com o positivo ao lado.
          Os testes 27 a 29 conferem a lista exata do permitido (permissões, papéis e policies): qualquer coisa a
          mais ou a menos aparece na mensagem.

Como rodar:
  - rodar DEPOIS do 09_administracao_seguranca_v1.sql;
  - tudo fica entre BEGIN e ROLLBACK: nenhum dado é alterado de verdade;
  - Roda inteiro com F5. Resultado na aba Messages: cada teste imprime "OK ..." ou "FALHOU ...".
    Esperado: 29 OK e nenhum FALHOU.

Por que SET ROLE: o bd2 é superusuário e superusuário ignora RLS e GRANT. Consultar como bd2 não prova nada.
SET ROLE troca o papel; RESET ROLE volta para o bd2. Dentro dos blocos DO dos testes, SET LOCAL ROLE troca o papel
só até o fim da transação.

10_administracao_seguranca_testes_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

BEGIN;

-- Turma usada nos testes de matrícula: CCO072 2026/2 A (a da demonstração de concorrência)
SELECT set_config('projeto_bd2.turma_teste',
       (SELECT t.id_turma::text
          FROM tb_turma t JOIN tb_disciplina d USING (id_disciplina) JOIN tb_periodo_letivo p USING (id_periodo_letivo)
         WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2 AND t.cd_turma = 'A'),
       true) AS turma_teste;

------------------------------------------------------------------------------------------------------------------------
-- PARTE 1 - DEMONSTRAÇÃO AO VIVO (aba Data Output)
-- Na apresentação: selecione cada bloco (do SET ROLE até o RESET ROLE, inclusive) e rode com F5, um por vez.

-- 1a) Como bd2 (superusuário): enxerga o histórico dos dois alunos
SELECT current_user AS quem_sou, cd_matricula, count(*) AS disciplinas_no_historico
  FROM vw_historico
 WHERE cd_matricula IN ('26000001', '26000012')
 GROUP BY cd_matricula
 ORDER BY cd_matricula;

-- 1b) Como o aluno 26000012: a MESMA consulta só devolve o histórico dele. O 26000001 sumiu.
SET ROLE aluno_26000012;
SELECT current_user AS quem_sou, cd_matricula, count(*) AS disciplinas_no_historico
  FROM vw_historico
 WHERE cd_matricula IN ('26000001', '26000012')
 GROUP BY cd_matricula
 ORDER BY cd_matricula;
RESET ROLE;

-- 1c) Como o aluno 26000012, pedindo SÓ o histórico do colega: zero linhas, sem erro.
--     O RLS não avisa que a linha existe: para o aluno, o histórico do outro simplesmente não existe.
SET ROLE aluno_26000012;
SELECT current_user AS quem_sou, *
  FROM vw_historico
 WHERE cd_matricula = '26000001';
RESET ROLE;

-- 1d) Como o aluno 26000012, vendo as vagas: a vw_vagas conta TODAS as matrículas da turma (não só as dele),
--     porque é uma view do dono. Ele vê quantas vagas sobram, mas não quem está matriculado.
SET ROLE aluno_26000012;
SELECT current_user AS quem_sou, ds_periodo, cd_disciplina, cd_turma, qt_vagas, qt_ocupadas, qt_livres, ds_situacao_vagas
  FROM vw_vagas
 WHERE cd_disciplina = 'CCO072' AND ic_periodo_atual
 ORDER BY cd_turma
 LIMIT 3;
RESET ROLE;


------------------------------------------------------------------------------------------------------------------------
-- PARTE 2 - TESTES AUTOMÁTICOS (aba Messages)
-- Teste negativo: o bloco tenta a ação proibida. Se passar, imprime FALHOU. Se o banco recusar com
-- insufficient_privilege (erro 42501, "permission denied"), imprime OK barrado.
-- Teste positivo que pode dar erro fica num bloco só dele: se der erro, imprime FALHOU (e não "OK barrado").

-- ALUNO -----------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_total_bd2   INT;
    v_total_aluno INT;
    v_alunos      INT;
    v_outro       INT;
    v_outro_matr  INT;
    v_ids_colega  INT[];
BEGIN
    -- positivo: o aluno vê o próprio histórico inteiro (mesma contagem que o bd2 vê para ele)
    SELECT count(*) INTO v_total_bd2 FROM vw_historico WHERE cd_matricula = '26000012';
    SET LOCAL ROLE aluno_26000012;
    SELECT count(*), count(DISTINCT cd_matricula) INTO v_total_aluno, v_alunos FROM vw_historico;
    RESET ROLE;
    IF v_total_aluno = v_total_bd2 AND v_total_aluno > 0 AND v_alunos = 1 THEN
        RAISE NOTICE 'OK (teste 1): aluno_26000012 ve o proprio historico inteiro (% linhas, 1 aluno)', v_total_aluno;
    ELSE
        RAISE NOTICE 'FALHOU (teste 1): aluno viu % linhas de % alunos, esperado % linhas de 1 aluno',
                     v_total_aluno, v_alunos, v_total_bd2;
    END IF;

    -- negativo: o histórico e as matrículas do colega não aparecem (controle: o bd2 vê que existem).
    -- Cada tabela é lida sozinha, pelos ids das matrículas do colega: assim o teste prova a policy de cada
    -- tabela, e não só a de tb_matricula (um JOIN esconderia uma policy de tb_historico liberando tudo).
    SELECT array_agg(m.id_matricula) INTO v_ids_colega
      FROM tb_matricula m JOIN tb_aluno a USING (id_aluno) WHERE a.cd_matricula = '26000001';
    SELECT count(*) INTO v_total_bd2 FROM tb_historico WHERE id_matricula = ANY (v_ids_colega);
    SET LOCAL ROLE aluno_26000012;
    SELECT count(*) INTO v_outro       FROM tb_historico WHERE id_matricula = ANY (v_ids_colega);
    SELECT count(*) INTO v_outro_matr  FROM tb_matricula WHERE id_matricula = ANY (v_ids_colega);
    RESET ROLE;
    IF v_total_bd2 > 0 AND v_outro = 0 AND v_outro_matr = 0 THEN
        RAISE NOTICE 'OK barrado (teste 2): historico do 26000001 existe (% linhas) e o aluno_26000012 ve 0 historicos e 0 matriculas dele',
                     v_total_bd2;
    ELSE
        RAISE NOTICE 'FALHOU (teste 2): bd2 ve %, aluno_26000012 ve % historicos e % matriculas do colega',
                     v_total_bd2, v_outro, v_outro_matr;
    END IF;

    -- negativo: lendo a tabela de alunos direto (sem view), só aparece ele mesmo
    SET LOCAL ROLE aluno_26000012;
    SELECT count(*) INTO v_alunos FROM tb_aluno;
    RESET ROLE;
    IF v_alunos = 1 THEN
        RAISE NOTICE 'OK barrado (teste 3): aluno_26000012 le tb_aluno direto e ve so 1 aluno (ele)';
    ELSE
        RAISE NOTICE 'FALHOU (teste 3): aluno_26000012 viu % alunos em tb_aluno', v_alunos;
    END IF;

    -- positivo: o outro aluno também vê o próprio (a policy não é fixa num aluno só)
    SET LOCAL ROLE aluno_26000001;
    SELECT count(*), count(DISTINCT cd_matricula) INTO v_total_aluno, v_alunos FROM vw_historico;
    RESET ROLE;
    IF v_total_aluno > 0 AND v_alunos = 1 THEN
        RAISE NOTICE 'OK (teste 4): aluno_26000001 ve o proprio historico (% linhas, 1 aluno)', v_total_aluno;
    ELSE
        RAISE NOTICE 'FALHOU (teste 4): aluno_26000001 viu % linhas de % alunos', v_total_aluno, v_alunos;
    END IF;

    -- positivo: vw_vagas conta todas as matrículas da turma mesmo para o aluno
    SELECT count(*) INTO v_total_bd2 FROM tb_matricula
     WHERE id_turma = current_setting('projeto_bd2.turma_teste')::int AND ds_status = 'ativa';
    SET LOCAL ROLE aluno_26000012;
    SELECT qt_ocupadas INTO v_total_aluno FROM vw_vagas
     WHERE cd_disciplina = 'CCO072' AND ds_periodo = '2026/2' AND cd_turma = 'A';
    RESET ROLE;
    IF v_total_aluno = v_total_bd2 AND v_total_bd2 > 1 THEN
        RAISE NOTICE 'OK (teste 5): aluno ve % vagas ocupadas na CCO072 2026/2 A, mesmo numero que o bd2', v_total_aluno;
    ELSE
        RAISE NOTICE 'FALHOU (teste 5): aluno ve % ocupadas, bd2 conta %', v_total_aluno, v_total_bd2;
    END IF;
END $$;

-- ações do aluno que precisam de erro: um bloco por ação, porque cada erro desfaz só o próprio bloco
DO $$
DECLARE
    v_coluna TEXT;
    v_lidas  TEXT[] := '{}';
BEGIN
    SET LOCAL ROLE aluno_26000012;
    -- Os testes de nota gravam o mesmo valor: o que importa é se o banco deixa alterar, e um valor novo poderia
    -- bater numa restrição CHECK do histórico e parar o script com outro erro.
    BEGIN
        UPDATE tb_historico SET qt_nota_a1 = qt_nota_a1 WHERE id_matricula IN (SELECT id_matricula FROM tb_matricula);
        RAISE NOTICE 'FALHOU (teste 6): aluno alterou a propria nota';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 6): aluno nao altera a propria nota: %', SQLERRM;
    END;
    BEGIN
        PERFORM count(*) FROM tb_log_matricula;
        RAISE NOTICE 'FALHOU (teste 7): aluno leu o log de matriculas';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 7): aluno nao le o log: %', SQLERRM;
    END;
    BEGIN
        PERFORM count(*) FROM mv_indicadores;
        RAISE NOTICE 'FALHOU (teste 8): aluno leu os indicadores da coordenacao';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 8): aluno nao le mv_indicadores: %', SQLERRM;
    END;
    BEGIN
        PERFORM fn_atualizar_indicadores();       -- o positivo é o teste 21 (coordenacao)
        RAISE NOTICE 'FALHOU (teste 9): aluno disparou a atualizacao dos indicadores';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 9): aluno nao atualiza os indicadores: %', SQLERRM;
    END;
    BEGIN
        PERFORM nm_professor, ds_titulacao FROM tb_professor LIMIT 1;
        IF FOUND THEN
            RAISE NOTICE 'OK (teste 10): aluno le nome e titulacao do professor';
        ELSE
            RAISE NOTICE 'FALHOU (teste 10): aluno nao achou nenhum professor';
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'FALHOU (teste 10): aluno nao conseguiu ler o nome do professor: %', SQLERRM;
    END;
    -- negativo: cada coluna protegida do professor, uma por uma
    FOREACH v_coluna IN ARRAY ARRAY['ds_email', 'cd_matricula'] LOOP
        BEGIN
            EXECUTE format('SELECT %I FROM tb_professor LIMIT 1', v_coluna);
            v_lidas := v_lidas || v_coluna;
        EXCEPTION WHEN insufficient_privilege THEN
            NULL;
        END;
    END LOOP;
    IF cardinality(v_lidas) = 0 THEN
        RAISE NOTICE 'OK barrado (teste 11): aluno nao le e-mail nem matricula do professor';
    ELSE
        RAISE NOTICE 'FALHOU (teste 11): aluno leu % do professor', v_lidas;
    END IF;
    BEGIN
        INSERT INTO tb_matricula (id_aluno, id_turma)
        VALUES ((SELECT min(id_aluno) FROM tb_aluno), current_setting('projeto_bd2.turma_teste')::int);
        RAISE NOTICE 'FALHOU (teste 12): aluno incluiu matricula direto na tabela';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 12): aluno nao inclui matricula: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- SECRETARIA ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_id_matricula INT;
    v_id_aluno     INT;
    v_id_historico INT;
    v_usuario      TEXT;
    v_sessao       TEXT;
    v_tabela       TEXT;
    v_antes        TEXT;
    v_depois       TEXT;
    v_novas        INT;
BEGIN
    SELECT min(id_matricula) INTO v_id_matricula FROM tb_matricula WHERE ds_status = 'ativa';
    SELECT id_aluno INTO v_id_aluno FROM tb_aluno WHERE cd_matricula = '26000001';
    SELECT min(id_historico) INTO v_id_historico FROM tb_historico WHERE ds_situacao = 'cursando' AND qt_nota_a2 IS NULL;

    SET LOCAL ROLE secretaria;

    -- positivo: tranca uma matrícula e o gatilho grava o log com o papel e o usuário da conexão
    UPDATE tb_matricula SET ds_status = 'trancada' WHERE id_matricula = v_id_matricula;
    SELECT nm_usuario, ds_detalhe ->> 'usuario_sessao', ds_detalhe ->> 'tabela',
           ds_detalhe -> 'antes' ->> 'ds_status', ds_detalhe -> 'depois' ->> 'ds_status'
      INTO v_usuario, v_sessao, v_tabela, v_antes, v_depois
      FROM tb_log_matricula
     WHERE id_matricula = v_id_matricula
     ORDER BY id_log_matricula DESC LIMIT 1;
    IF v_usuario = 'secretaria' AND v_sessao = session_user AND v_tabela = 'tb_matricula'
       AND v_antes = 'ativa' AND v_depois = 'trancada' THEN
        RAISE NOTICE 'OK (teste 13): secretaria trancou a matricula % e o log gravou: papel %, conexao %, % -> %',
                     v_id_matricula, v_usuario, v_sessao, v_antes, v_depois;
    ELSE
        RAISE NOTICE 'FALHOU (teste 13): log gravou papel %, conexao %, tabela %, % -> %',
                     v_usuario, v_sessao, v_tabela, v_antes, v_depois;
    END IF;

    -- positivo: matricula um aluno (o id vem da IDENTITY, sem permissão extra na sequence)
    INSERT INTO tb_matricula (id_aluno, id_turma) VALUES (v_id_aluno, current_setting('projeto_bd2.turma_teste')::int);
    GET DIAGNOSTICS v_novas = ROW_COUNT;
    IF v_novas = 1 THEN
        RAISE NOTICE 'OK (teste 14): secretaria matriculou o 26000001 na CCO072 2026/2 A';
    ELSE
        RAISE NOTICE 'FALHOU (teste 14): INSERT gravou % linhas', v_novas;
    END IF;

    -- positivo: lança a nota A2 e o log das notas grava o antes e o depois
    UPDATE tb_historico SET qt_nota_a2 = 8 WHERE id_historico = v_id_historico;
    SELECT ds_detalhe ->> 'tabela', ds_detalhe -> 'antes' ->> 'qt_nota_a2', ds_detalhe -> 'depois' ->> 'qt_nota_a2'
      INTO v_tabela, v_antes, v_depois
      FROM tb_log_matricula
     ORDER BY id_log_matricula DESC LIMIT 1;
    IF v_tabela = 'tb_historico' AND v_antes IS NULL AND v_depois::numeric = 8 THEN
        RAISE NOTICE 'OK (teste 15): secretaria lancou a nota A2 do historico % e o log gravou: vazia -> %',
                     v_id_historico, v_depois;
    ELSE
        RAISE NOTICE 'FALHOU (teste 15): log das notas gravou tabela %, % -> %', v_tabela, v_antes, v_depois;
    END IF;

    RESET ROLE;
END $$;

DO $$
BEGIN
    SET LOCAL ROLE secretaria;
    BEGIN
        DELETE FROM tb_matricula WHERE id_matricula = (SELECT min(id_matricula) FROM tb_matricula);
        RAISE NOTICE 'FALHOU (teste 16): secretaria apagou uma matricula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 16): secretaria nao apaga matricula (so tranca ou cancela): %', SQLERRM;
    END;
    BEGIN
        UPDATE tb_matricula SET id_turma = id_turma WHERE id_matricula = (SELECT min(id_matricula) FROM tb_matricula);
        RAISE NOTICE 'FALHOU (teste 17): secretaria trocou a turma de uma matricula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 17): secretaria so altera o status da matricula: %', SQLERRM;
    END;
    BEGIN
        INSERT INTO tb_log_matricula (id_matricula, ds_acao, ds_detalhe, nm_usuario)
        VALUES (1, 'UPDATE', '{}', 'coordenacao');
        RAISE NOTICE 'FALHOU (teste 18): secretaria gravou log em nome de outro usuario';
    EXCEPTION WHEN insufficient_privilege THEN
        -- quem tem que barrar aqui é a permissão por coluna (nm_usuario fora do GRANT), não a trava do teste 19
        IF SQLERRM LIKE 'permission denied for table tb_log_matricula%' THEN
            RAISE NOTICE 'OK barrado (teste 18): ninguem grava log em nome de outro: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FALHOU (teste 18): barrado so pela trava do gatilho, a permissao por coluna deixou: %', SQLERRM;
        END IF;
    END;
    -- negativo: INSERT direto no log só com as colunas que ela tem permissão, inventando o antes e o depois.
    -- O positivo ao lado é o teste 13 (o log gravado pelo gatilho, com o mesmo papel).
    BEGIN
        INSERT INTO tb_log_matricula (id_matricula, ds_acao, ds_detalhe)
        VALUES (1, 'UPDATE', '{"antes": {"ds_status": "cancelada"}, "depois": {"ds_status": "ativa"}}');
        RAISE NOTICE 'FALHOU (teste 19): secretaria inventou uma linha de log com INSERT direto';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM LIKE '%so recebe linha do gatilho%' THEN
            RAISE NOTICE 'OK barrado (teste 19): log nao aceita INSERT direto: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FALHOU (teste 19): barrado por outro motivo (o INSERT nessas colunas devia ser permitido): %', SQLERRM;
        END IF;
    END;
    BEGIN
        UPDATE tb_log_matricula SET ds_acao = 'DELETE' WHERE id_log_matricula = 1;
        RAISE NOTICE 'FALHOU (teste 20): secretaria editou o log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 20): log nao se edita: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- COORDENAÇÃO -----------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_linhas INT;
    v_quando TIMESTAMPTZ;
    v_coluna TEXT;
    v_lidas  TEXT[] := '{}';
BEGIN
    SET LOCAL ROLE coordenacao;

    -- positivo: lê os indicadores e dispara a atualização pela função (sem ser dona da materialized view)
    SELECT count(*) INTO v_linhas FROM mv_indicadores;
    v_quando := fn_atualizar_indicadores();
    IF v_linhas > 0 AND v_quando IS NOT NULL THEN
        RAISE NOTICE 'OK (teste 21): coordenacao le % linhas de indicadores e atualizou em %', v_linhas, v_quando;
    ELSE
        RAISE NOTICE 'FALHOU (teste 21): coordenacao leu % linhas, atualizacao %', v_linhas, v_quando;
    END IF;

    -- positivo: vê o histórico de todos os alunos
    SELECT count(DISTINCT cd_matricula) INTO v_linhas FROM vw_historico;
    IF v_linhas > 1 THEN
        RAISE NOTICE 'OK (teste 22): coordenacao ve o historico de % alunos', v_linhas;
    ELSE
        RAISE NOTICE 'FALHOU (teste 22): coordenacao ve o historico de % alunos', v_linhas;
    END IF;

    BEGIN
        PERFORM nm_aluno, cd_matricula FROM tb_aluno LIMIT 1;
        IF FOUND THEN
            RAISE NOTICE 'OK (teste 23): coordenacao le nome e matricula do aluno';
        ELSE
            RAISE NOTICE 'FALHOU (teste 23): coordenacao nao achou nenhum aluno';
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'FALHOU (teste 23): coordenacao nao conseguiu ler o nome do aluno: %', SQLERRM;
    END;
    -- negativo: cada dado pessoal, um por um
    FOREACH v_coluna IN ARRAY ARRAY['cd_cpf', 'ds_email', 'dt_nascimento'] LOOP
        BEGIN
            EXECUTE format('SELECT %I FROM tb_aluno LIMIT 1', v_coluna);
            v_lidas := v_lidas || v_coluna;
        EXCEPTION WHEN insufficient_privilege THEN
            NULL;
        END;
    END LOOP;
    IF cardinality(v_lidas) = 0 THEN
        RAISE NOTICE 'OK barrado (teste 24): coordenacao nao le CPF, e-mail nem nascimento do aluno';
    ELSE
        RAISE NOTICE 'FALHOU (teste 24): coordenacao leu % do aluno', v_lidas;
    END IF;
    BEGIN
        UPDATE tb_historico SET qt_nota_a1 = qt_nota_a1 WHERE id_historico = 1;
        RAISE NOTICE 'FALHOU (teste 25): coordenacao alterou nota';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 25): coordenacao nao altera nota: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- QUALQUER OUTRO USUÁRIO (negado por padrão) ----------------------------------------------------------------------------
-- Um usuário novo, sem papel nenhum, não enxerga nada. O CREATE ROLE também é desfeito pelo ROLLBACK.
CREATE ROLE visitante_teste NOLOGIN;
DO $$
BEGIN
    SET LOCAL ROLE visitante_teste;
    BEGIN
        PERFORM count(*) FROM projeto_bd2.vw_oferta;
        RAISE NOTICE 'FALHOU (teste 26): usuario sem papel leu a oferta';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 26): usuario sem papel nao le nada: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- LISTA EXATA DO PERMITIDO ----------------------------------------------------------------------------------------------
-- Os testes acima tentam ações escolhidas. Os três de baixo conferem TUDO contra uma lista escrita aqui, e qualquer
-- diferença aparece na mensagem ("sobrando" = o banco permite e a lista não; "faltando" = o contrário).

-- Teste 27: a matriz de acesso do cabeçalho do 09_administracao_seguranca_v1.sql, lida do banco (has_*_privilege).
-- Cobre tabelas, views e materialized view (coluna por coluna quando a permissão é só de algumas colunas),
-- sequences, funções e o schema. Os dois alunos de teste têm que ter exatamente o que o grupo aluno tem, e o
-- visitante_teste (só PUBLIC) não pode ter nada.
DO $$
DECLARE
    v_diferencas TEXT;
BEGIN
    WITH papeis(papel) AS (
        VALUES ('aluno'), ('aluno_26000001'), ('aluno_26000012'), ('secretaria'), ('coordenacao'), ('visitante_teste')
    ),
    esperado_aluno(objeto, privilegio) AS (
        SELECT unnest(ARRAY['vw_oferta', 'vw_vagas', 'vw_historico', 'tb_turma', 'tb_disciplina', 'tb_periodo_letivo',
                            'tb_turma_horario', 'tb_sala', 'tb_curso', 'tb_aluno', 'tb_matricula', 'tb_historico']),
               'SELECT'
        UNION ALL SELECT 'tb_professor', 'SELECT (ds_titulacao, id_professor, nm_professor)'
        UNION ALL SELECT 'fn_matricula_do_usuario', 'EXECUTE'
        UNION ALL SELECT 'schema projeto_bd2', 'USAGE'
    ),
    esperado(papel, objeto, privilegio) AS (
        SELECT p.papel, e.objeto, e.privilegio
          FROM esperado_aluno e CROSS JOIN (VALUES ('aluno'), ('aluno_26000001'), ('aluno_26000012')) AS p(papel)
        UNION ALL
        SELECT 'secretaria', c.relname::text, 'SELECT'
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm')
        UNION ALL SELECT 'secretaria', unnest(ARRAY['tb_aluno', 'tb_historico', 'tb_matricula']), 'INSERT'
        UNION ALL SELECT 'secretaria', unnest(ARRAY['tb_aluno', 'tb_historico']), 'UPDATE'
        UNION ALL SELECT 'secretaria', 'tb_matricula', 'UPDATE (ds_status)'
        UNION ALL SELECT 'secretaria', 'tb_log_matricula', 'INSERT (ds_acao, ds_detalhe, id_matricula)'
        UNION ALL SELECT 'secretaria', 'schema projeto_bd2', 'USAGE'
        UNION ALL
        SELECT 'coordenacao', unnest(ARRAY['vw_oferta', 'vw_vagas', 'vw_historico', 'mv_indicadores', 'tb_turma',
                                           'tb_disciplina', 'tb_periodo_letivo', 'tb_turma_horario', 'tb_sala',
                                           'tb_curso', 'tb_matricula', 'tb_historico', 'tb_log_matricula',
                                           'tb_professor', 'tb_curriculo', 'tb_curriculo_disciplina',
                                           'tb_pre_requisito']), 'SELECT'
        UNION ALL SELECT 'coordenacao', 'tb_aluno',
                         'SELECT (cd_matricula, dt_ingresso, ic_ativo, id_aluno, id_curriculo, id_curso, nm_aluno)'
        UNION ALL SELECT 'coordenacao', 'fn_atualizar_indicadores', 'EXECUTE'
        UNION ALL SELECT 'coordenacao', 'schema projeto_bd2', 'USAGE'
    ),
    real AS (
        -- tabelas, views e materialized view: a tabela inteira, ou a lista das colunas liberadas
        SELECT r.papel, c.relname::text AS objeto,
               CASE WHEN has_table_privilege(r.papel, c.oid, p.priv) THEN p.priv
                    ELSE p.priv || ' (' || (SELECT string_agg(a.attname::text, ', ' ORDER BY a.attname)
                                              FROM pg_attribute a
                                             WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                                               AND has_column_privilege(r.papel, c.oid, a.attnum, p.priv)) || ')'
               END AS privilegio
          FROM papeis r
         CROSS JOIN pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                            ('REFERENCES'), ('TRIGGER')) AS p(priv)
         WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm')
           AND (has_table_privilege(r.papel, c.oid, p.priv)
                OR (p.priv IN ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
                    AND has_any_column_privilege(r.papel, c.oid, p.priv)))
        UNION ALL
        -- sequences (ninguém precisa: as colunas IDENTITY geram o id sem permissão na sequence)
        SELECT r.papel, c.relname::text, p.priv
          FROM papeis r
         CROSS JOIN pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         CROSS JOIN (VALUES ('USAGE'), ('SELECT'), ('UPDATE')) AS p(priv)
         WHERE n.nspname = 'projeto_bd2' AND c.relkind = 'S'
           AND has_sequence_privilege(r.papel, c.oid, p.priv)
        UNION ALL
        -- funções
        SELECT r.papel, f.proname::text, 'EXECUTE'
          FROM papeis r
         CROSS JOIN pg_proc f
          JOIN pg_namespace n ON n.oid = f.pronamespace
         WHERE n.nspname = 'projeto_bd2'
           AND has_function_privilege(r.papel, f.oid, 'EXECUTE')
        UNION ALL
        -- schema: USAGE (entrar) e CREATE (criar objeto dentro)
        SELECT r.papel, 'schema projeto_bd2', p.priv
          FROM papeis r
         CROSS JOIN (VALUES ('USAGE'), ('CREATE')) AS p(priv)
         WHERE has_schema_privilege(r.papel, 'projeto_bd2', p.priv)
    ),
    diferenca AS (
        (SELECT 'sobrando: '  || papel || ' ' || privilegio || ' em ' || objeto AS linha FROM real
         EXCEPT SELECT 'sobrando: '  || papel || ' ' || privilegio || ' em ' || objeto FROM esperado)
        UNION ALL
        (SELECT 'faltando: ' || papel || ' ' || privilegio || ' em ' || objeto FROM esperado
         EXCEPT SELECT 'faltando: ' || papel || ' ' || privilegio || ' em ' || objeto FROM real)
    )
    SELECT string_agg(linha, '; ' ORDER BY linha) INTO v_diferencas FROM diferenca;

    IF v_diferencas IS NULL THEN
        RAISE NOTICE 'OK (teste 27): permissoes (tabelas, colunas, sequences, funcoes e schema) batem exatamente com a matriz de acesso';
    ELSE
        RAISE NOTICE 'FALHOU (teste 27): %', v_diferencas;
    END IF;
END $$;

-- Teste 28: atributos e grupos dos papéis. Nenhum pode conectar, ser superusuário, ignorar RLS (BYPASSRLS) ou
-- criar papel e banco; os dois alunos de teste são membros só do grupo aluno, e os grupos não são membros de nada.
DO $$
DECLARE
    v_diferencas TEXT;
BEGIN
    WITH esperado(linha) AS (
        VALUES ('aluno_26000001 membro de aluno'), ('aluno_26000012 membro de aluno')
    ),
    nossos AS (
        SELECT * FROM pg_roles
         WHERE rolname IN ('aluno', 'secretaria', 'coordenacao', 'aluno_26000001', 'aluno_26000012')
    ),
    real(linha) AS (
        SELECT r.rolname || ' atributo ' || a.atributo
          FROM nossos r
         CROSS JOIN LATERAL (VALUES ('LOGIN', r.rolcanlogin), ('SUPERUSER', r.rolsuper), ('BYPASSRLS', r.rolbypassrls),
                                    ('CREATEROLE', r.rolcreaterole), ('CREATEDB', r.rolcreatedb),
                                    ('REPLICATION', r.rolreplication), ('NOINHERIT', NOT r.rolinherit)) AS a(atributo, ligado)
         WHERE a.ligado
        UNION ALL
        SELECT r.rolname || ' membro de ' || g.rolname || CASE WHEN am.admin_option THEN ' com ADMIN' ELSE '' END
          FROM nossos r
          JOIN pg_auth_members am ON am.member = r.oid
          JOIN pg_roles g ON g.oid = am.roleid
    ),
    diferenca AS (
        (SELECT 'sobrando: ' || linha AS linha FROM real EXCEPT SELECT 'sobrando: ' || linha FROM esperado)
        UNION ALL
        (SELECT 'faltando: ' || linha FROM esperado EXCEPT SELECT 'faltando: ' || linha FROM real)
    )
    SELECT string_agg(linha, '; ' ORDER BY linha) INTO v_diferencas FROM diferenca;

    IF v_diferencas IS NULL THEN
        RAISE NOTICE 'OK (teste 28): papeis sem LOGIN, SUPERUSER e BYPASSRLS, e os alunos de teste so no grupo aluno';
    ELSE
        RAISE NOTICE 'FALHOU (teste 28): %', v_diferencas;
    END IF;
END $$;

-- Teste 29: policies do schema e RLS. Policies que liberam linha se somam (basta uma liberar), então uma policy a
-- mais, mesmo com outro nome, abriria o RLS. O comportamento de cada policy é provado nos testes 1 a 4.
DO $$
DECLARE
    v_diferencas TEXT;
BEGIN
    WITH esperado(linha) AS (
        VALUES ('tb_aluno: RLS ligado e forcado'), ('tb_matricula: RLS ligado e forcado'),
               ('tb_historico: RLS ligado e forcado'),
               ('tb_aluno: pol_aluno_proprio_cadastro SELECT para aluno'),
               ('tb_aluno: pol_secretaria_aluno ALL para secretaria'),
               ('tb_aluno: pol_coordenacao_aluno SELECT para coordenacao'),
               ('tb_matricula: pol_aluno_proprias_matriculas SELECT para aluno'),
               ('tb_matricula: pol_secretaria_matricula ALL para secretaria'),
               ('tb_matricula: pol_coordenacao_matricula SELECT para coordenacao'),
               ('tb_historico: pol_aluno_proprio_historico SELECT para aluno'),
               ('tb_historico: pol_secretaria_historico ALL para secretaria'),
               ('tb_historico: pol_coordenacao_historico SELECT para coordenacao')
    ),
    real(linha) AS (
        SELECT c.relname || ': RLS '
               || CASE WHEN c.relrowsecurity THEN 'ligado' ELSE 'desligado' END
               || CASE WHEN c.relforcerowsecurity THEN ' e forcado' ELSE ' sem forcar' END
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'projeto_bd2' AND c.relkind = 'r'
           AND (c.relrowsecurity OR c.relforcerowsecurity OR c.relname IN ('tb_aluno', 'tb_matricula', 'tb_historico'))
        UNION ALL
        SELECT tablename || ': ' || policyname || ' ' || cmd || ' para ' || array_to_string(roles, ', ')
               || CASE WHEN permissive = 'PERMISSIVE' THEN '' ELSE ' (restritiva)' END
          FROM pg_policies
         WHERE schemaname = 'projeto_bd2'
    ),
    diferenca AS (
        (SELECT 'sobrando: ' || linha AS linha FROM real EXCEPT SELECT 'sobrando: ' || linha FROM esperado)
        UNION ALL
        (SELECT 'faltando: ' || linha FROM esperado EXCEPT SELECT 'faltando: ' || linha FROM real)
    )
    SELECT string_agg(linha, '; ' ORDER BY linha) INTO v_diferencas FROM diferenca;

    IF v_diferencas IS NULL THEN
        RAISE NOTICE 'OK (teste 29): RLS ligado e forcado nas 3 tabelas, com exatamente as 9 policies da matriz';
    ELSE
        RAISE NOTICE 'FALHOU (teste 29): %', v_diferencas;
    END IF;
END $$;

ROLLBACK;

-- Conferência do ROLLBACK: o papel de teste não ficou no banco (esperado: 0)
SELECT count(*) AS visitante_teste_sobrou FROM pg_roles WHERE rolname = 'visitante_teste';
