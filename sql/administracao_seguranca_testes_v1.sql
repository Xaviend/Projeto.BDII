/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: provar que os papéis, os GRANT/REVOKE e o RLS do administracao_seguranca_v1.sql funcionam.
          Cada teste troca de papel com SET ROLE e confere o resultado:
            - o que DEVE funcionar funciona (teste positivo) e
            - o que DEVE ser barrado é barrado (teste negativo), sempre com o positivo ao lado.

Como rodar:
  - rodar DEPOIS do administracao_seguranca_v1.sql;
  - tudo fica entre BEGIN e ROLLBACK: nenhum dado é alterado de verdade;
  - Roda inteiro com F5. Resultado na aba Messages: cada teste imprime "OK ..." ou "FALHOU ...".
    Esperado: nenhum FALHOU.

Por que SET ROLE: o bd2 é superusuário e superusuário ignora RLS e GRANT. Consultar como bd2 não prova nada.
SET LOCAL ROLE troca o papel só até o fim da transação; RESET ROLE volta para o bd2.

administracao_seguranca_testes_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

BEGIN;

------------------------------------------------------------------------------------------------------------------------
-- PARTE 1 - DEMONSTRAÇÃO AO VIVO (aba Data Output)
-- Na apresentação: selecione cada bloco (do SET ao RESET) e rode com F5, um por vez.

-- 1a) Como bd2 (superusuário): enxerga o histórico dos dois alunos
SELECT current_user AS quem_sou, cd_matricula, count(*) AS disciplinas_no_historico
  FROM vw_historico
 WHERE cd_matricula IN ('26000001', '26000012')
 GROUP BY cd_matricula
 ORDER BY cd_matricula;

-- 1b) Como o aluno 26000012: a MESMA consulta só devolve o histórico dele. O 26000001 sumiu.
SET LOCAL ROLE aluno_26000012;
SELECT current_user AS quem_sou, cd_matricula, count(*) AS disciplinas_no_historico
  FROM vw_historico
 WHERE cd_matricula IN ('26000001', '26000012')
 GROUP BY cd_matricula
 ORDER BY cd_matricula;
RESET ROLE;

-- 1c) Como o aluno 26000012, pedindo SÓ o histórico do colega: zero linhas, sem erro.
--     O RLS não avisa que a linha existe: para o aluno, o histórico do outro simplesmente não existe.
SET LOCAL ROLE aluno_26000012;
SELECT current_user AS quem_sou, *
  FROM vw_historico
 WHERE cd_matricula = '26000001';
RESET ROLE;

-- 1d) Como o aluno 26000012, vendo as vagas: a vw_vagas conta TODAS as matrículas da turma (não só as dele),
--     porque é uma view do dono. Ele vê quantas vagas sobram, mas não quem está matriculado.
SET LOCAL ROLE aluno_26000012;
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
    SELECT count(*) INTO v_total_bd2 FROM tb_matricula m JOIN tb_turma t USING (id_turma)
      JOIN tb_disciplina d USING (id_disciplina) JOIN tb_periodo_letivo p USING (id_periodo_letivo)
     WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2 AND t.cd_turma = 'A'
       AND m.ds_status = 'ativa';
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

-- negativos do aluno que precisam de erro: um bloco por ação, porque cada erro desfaz só o próprio bloco
DO $$
BEGIN
    SET LOCAL ROLE aluno_26000012;
    BEGIN
        UPDATE tb_historico SET qt_nota_a1 = 10 WHERE id_matricula IN (SELECT id_matricula FROM tb_matricula);
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
        PERFORM nm_professor FROM tb_professor LIMIT 1;           -- positivo: nome do professor pode
        PERFORM ds_email FROM tb_professor LIMIT 1;               -- negativo: e-mail do professor não
        RAISE NOTICE 'FALHOU (teste 9): aluno leu o e-mail do professor';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 9): aluno le o nome do professor mas nao o e-mail: %', SQLERRM;
    END;
    BEGIN
        INSERT INTO tb_matricula (id_aluno, id_turma) VALUES (1, 1529);
        RAISE NOTICE 'FALHOU (teste 10): aluno incluiu matricula direto na tabela';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 10): aluno nao inclui matricula: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- SECRETARIA ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_id_matricula INT;
    v_id_aluno     INT;
    v_usuario      TEXT;
    v_antes        TEXT;
    v_depois       TEXT;
    v_novas        INT;
BEGIN
    SELECT min(id_matricula) INTO v_id_matricula FROM tb_matricula WHERE ds_status = 'ativa';
    SELECT id_aluno INTO v_id_aluno FROM tb_aluno WHERE cd_matricula = '26000001';

    SET LOCAL ROLE secretaria;

    -- positivo: tranca uma matrícula e o gatilho grava o log com o usuário certo
    UPDATE tb_matricula SET ds_status = 'trancada' WHERE id_matricula = v_id_matricula;
    SELECT nm_usuario, ds_detalhe -> 'antes' ->> 'ds_status', ds_detalhe -> 'depois' ->> 'ds_status'
      INTO v_usuario, v_antes, v_depois
      FROM tb_log_matricula
     WHERE id_matricula = v_id_matricula
     ORDER BY id_log_matricula DESC LIMIT 1;
    IF v_usuario = 'secretaria' AND v_antes = 'ativa' AND v_depois = 'trancada' THEN
        RAISE NOTICE 'OK (teste 11): secretaria trancou a matricula % e o log gravou: usuario %, % -> %',
                     v_id_matricula, v_usuario, v_antes, v_depois;
    ELSE
        RAISE NOTICE 'FALHOU (teste 11): log gravou usuario %, % -> %', v_usuario, v_antes, v_depois;
    END IF;

    -- positivo: matricula um aluno (o id vem da IDENTITY, sem permissão extra na sequence)
    INSERT INTO tb_matricula (id_aluno, id_turma) VALUES (v_id_aluno, 1529);
    GET DIAGNOSTICS v_novas = ROW_COUNT;
    IF v_novas = 1 THEN
        RAISE NOTICE 'OK (teste 12): secretaria matriculou o 26000001 na CCO072 2026/2 A';
    ELSE
        RAISE NOTICE 'FALHOU (teste 12): INSERT gravou % linhas', v_novas;
    END IF;

    RESET ROLE;
END $$;

DO $$
BEGIN
    SET LOCAL ROLE secretaria;
    BEGIN
        DELETE FROM tb_matricula WHERE id_matricula = (SELECT min(id_matricula) FROM tb_matricula);
        RAISE NOTICE 'FALHOU (teste 13): secretaria apagou uma matricula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 13): secretaria nao apaga matricula (so tranca ou cancela): %', SQLERRM;
    END;
    BEGIN
        UPDATE tb_matricula SET id_turma = id_turma WHERE id_matricula = (SELECT min(id_matricula) FROM tb_matricula);
        RAISE NOTICE 'FALHOU (teste 14): secretaria trocou a turma de uma matricula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 14): secretaria so altera o status da matricula: %', SQLERRM;
    END;
    BEGIN
        INSERT INTO tb_log_matricula (id_matricula, ds_acao, ds_detalhe, nm_usuario)
        VALUES (1, 'UPDATE', '{}', 'coordenacao');
        RAISE NOTICE 'FALHOU (teste 15): secretaria gravou log em nome de outro usuario';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 15): ninguem grava log em nome de outro: %', SQLERRM;
    END;
    BEGIN
        UPDATE tb_log_matricula SET ds_acao = 'DELETE' WHERE id_log_matricula = 1;
        RAISE NOTICE 'FALHOU (teste 16): secretaria editou o log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 16): log nao se edita: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- COORDENAÇÃO -----------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_linhas INT;
    v_quando TIMESTAMPTZ;
BEGIN
    SET LOCAL ROLE coordenacao;

    -- positivo: lê os indicadores e dispara a atualização pela função (sem ser dona da materialized view)
    SELECT count(*) INTO v_linhas FROM mv_indicadores;
    v_quando := fn_atualizar_indicadores();
    IF v_linhas > 0 AND v_quando IS NOT NULL THEN
        RAISE NOTICE 'OK (teste 17): coordenacao le % linhas de indicadores e atualizou em %', v_linhas, v_quando;
    ELSE
        RAISE NOTICE 'FALHOU (teste 17): coordenacao leu % linhas, atualizacao %', v_linhas, v_quando;
    END IF;

    -- positivo: vê o histórico de todos os alunos
    SELECT count(DISTINCT cd_matricula) INTO v_linhas FROM vw_historico;
    IF v_linhas > 1 THEN
        RAISE NOTICE 'OK (teste 18): coordenacao ve o historico de % alunos', v_linhas;
    ELSE
        RAISE NOTICE 'FALHOU (teste 18): coordenacao ve o historico de % alunos', v_linhas;
    END IF;

    BEGIN
        PERFORM nm_aluno FROM tb_aluno LIMIT 1;                  -- positivo: nome do aluno pode
        PERFORM cd_cpf FROM tb_aluno LIMIT 1;                    -- negativo: CPF não
        RAISE NOTICE 'FALHOU (teste 19): coordenacao leu o CPF do aluno';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 19): coordenacao le o nome do aluno mas nao o CPF: %', SQLERRM;
    END;
    BEGIN
        UPDATE tb_historico SET qt_nota_a1 = 10 WHERE id_historico = 1;
        RAISE NOTICE 'FALHOU (teste 20): coordenacao alterou nota';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 20): coordenacao nao altera nota: %', SQLERRM;
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
        RAISE NOTICE 'FALHOU (teste 21): usuario sem papel leu a oferta';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK barrado (teste 21): usuario sem papel nao le nada: %', SQLERRM;
    END;
    RESET ROLE;
END $$;

-- LISTA EXATA DO PERMITIDO ----------------------------------------------------------------------------------------------
-- Os testes acima tentam ações escolhidas. Este confere TUDO: monta a matriz de acesso esperada (a do cabeçalho do
-- administracao_seguranca_v1.sql) e compara com o que o banco diz que cada papel pode fazer (has_*_privilege).
-- Qualquer permissão a mais ou a menos aparece na mensagem. O visitante_teste (PUBLIC) não pode ter nenhuma.
DO $$
DECLARE
    v_diferencas TEXT;
BEGIN
    WITH esperado(papel, objeto, privilegio) AS (
        SELECT 'aluno', unnest(ARRAY['vw_oferta', 'vw_vagas', 'vw_historico', 'tb_turma', 'tb_disciplina',
                                     'tb_periodo_letivo', 'tb_turma_horario', 'tb_sala', 'tb_curso',
                                     'tb_aluno', 'tb_matricula', 'tb_historico']), 'SELECT'
        UNION ALL SELECT 'aluno', 'tb_professor', 'SELECT (colunas)'
        UNION ALL
        SELECT 'secretaria', c.relname::text, 'SELECT'
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm')
        UNION ALL SELECT 'secretaria', unnest(ARRAY['tb_aluno', 'tb_historico', 'tb_matricula']), 'INSERT'
        UNION ALL SELECT 'secretaria', unnest(ARRAY['tb_aluno', 'tb_historico']), 'UPDATE'
        UNION ALL SELECT 'secretaria', 'tb_matricula', 'UPDATE (colunas)'
        UNION ALL SELECT 'secretaria', 'tb_log_matricula', 'INSERT (colunas)'
        UNION ALL
        SELECT 'coordenacao', unnest(ARRAY['vw_oferta', 'vw_vagas', 'vw_historico', 'mv_indicadores', 'tb_turma',
                                           'tb_disciplina', 'tb_periodo_letivo', 'tb_turma_horario', 'tb_sala',
                                           'tb_curso', 'tb_matricula', 'tb_historico', 'tb_log_matricula',
                                           'tb_professor', 'tb_curriculo', 'tb_curriculo_disciplina',
                                           'tb_pre_requisito']), 'SELECT'
        UNION ALL SELECT 'coordenacao', 'tb_aluno', 'SELECT (colunas)'
        UNION ALL SELECT unnest(ARRAY['aluno', 'secretaria', 'coordenacao']), 'schema projeto_bd2', 'USAGE'
    ),
    real AS (
        SELECT r.papel, c.relname::text AS objeto,
               CASE WHEN has_table_privilege(r.papel, c.oid, p.priv) THEN p.priv
                    ELSE p.priv || ' (colunas)' END AS privilegio
          FROM (VALUES ('aluno'), ('secretaria'), ('coordenacao'), ('visitante_teste')) AS r(papel)
         CROSS JOIN pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                            ('REFERENCES'), ('TRIGGER')) AS p(priv)
         WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm')
           AND (has_table_privilege(r.papel, c.oid, p.priv)
                OR (p.priv IN ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
                    AND has_any_column_privilege(r.papel, c.oid, p.priv)))
        UNION ALL
        SELECT r.papel, 'schema projeto_bd2', 'USAGE'
          FROM (VALUES ('aluno'), ('secretaria'), ('coordenacao'), ('visitante_teste')) AS r(papel)
         WHERE has_schema_privilege(r.papel, 'projeto_bd2', 'USAGE')
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
        RAISE NOTICE 'OK (teste 22): permissoes de aluno, secretaria, coordenacao e PUBLIC batem exatamente com a matriz de acesso';
    ELSE
        RAISE NOTICE 'FALHOU (teste 22): %', v_diferencas;
    END IF;
END $$;

ROLLBACK;

-- Conferência do ROLLBACK: o papel de teste não ficou no banco (esperado: 0)
SELECT count(*) AS visitante_teste_sobrou FROM pg_roles WHERE rolname = 'visitante_teste';
