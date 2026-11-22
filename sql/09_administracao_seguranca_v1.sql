/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: controle de acesso do Marco 2:
          (1) papéis (roles) aluno, secretaria e coordenacao;
          (2) REVOKE de tudo e GRANT só do necessário para cada papel, inclusive por coluna;
          (3) RLS (Row Level Security): o aluno só enxerga as próprias linhas de tb_aluno, tb_matricula e
              tb_historico. É isso que impede um aluno de ver o histórico de outro.

Como rodar:
  - rodar DEPOIS de todos os outros scripts (modelo, carga, índices, views e auditoria): ele fecha as permissões
    de tudo que já existe no schema;
  - pode rodar quantas vezes quiser, e cada rodada desfaz mudança feita à mão: CREATE ROLE só se não existir e
    ALTER ROLE acerta os atributos, os papéis saem de qualquer grupo que não seja o deles, REVOKE de tudo antes
    dos GRANT, e todas as policies das tabelas com RLS são apagadas antes de criar as daqui.
  Os testes ficam em 10_administracao_seguranca_testes_v1.sql.

Como o banco sabe quem é o aluno:
  cada aluno tem um usuário (role) próprio chamado aluno_<matrícula>, membro do papel aluno.
  Ex.: o aluno de matrícula 26000012 entra como aluno_26000012. A policy compara a matrícula da linha com o nome
  do usuário conectado (current_user). Para a demonstração criamos dois alunos: aluno_26000001 e aluno_26000012.
  Na vida real cada funcionário também teria um usuário próprio com LOGIN, membro de secretaria ou de coordenacao.
  Aqui os papéis são NOLOGIN (ninguém conecta com eles e não existe senha no repositório): a demonstração usa
  SET ROLE a partir do usuário bd2.

ATENÇÃO: o bd2 é SUPERUSUÁRIO no ambiente Docker. Superusuário ignora RLS e GRANT sempre, mesmo com FORCE.
         Por isso os testes trocam de papel com SET ROLE: rodar a consulta como bd2 não prova nada.

Matriz de acesso (o que cada papel pode fazer):
  tabela / objeto                  | aluno                    | secretaria              | coordenacao
  ---------------------------------+--------------------------+-------------------------+-------------------------
  vw_oferta, vw_vagas              | lê                       | lê                      | lê
  vw_historico                     | lê só o próprio (RLS)    | lê tudo                 | lê tudo
  mv_indicadores                   | -                        | lê                      | lê e atualiza (função)
  tb_aluno                         | lê só o próprio (RLS)    | lê, inclui, altera      | lê sem CPF/e-mail/nasc.
  tb_matricula                     | lê só as próprias (RLS)  | lê, inclui, só o status | lê
  tb_historico                     | lê só o próprio (RLS)    | lê, inclui, altera      | lê
  tb_log_matricula                 | -                        | lê (inclui só o gatilho)| lê
  funções                          | fn_matricula_do_usuario  | -                       | fn_atualizar_indicadores
  turma, disciplina, período, sala | lê (catálogo de oferta)  | lê                      | lê
  tb_professor                     | lê só nome e titulação   | lê                      | lê
  DELETE em qualquer tabela        | -                        | -                       | -
  (matrícula não se apaga: muda o status para trancada ou cancelada, e o log guarda o antes e o depois)

administracao_seguranca_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - PAPÉIS (ROLES)
-- Role é usuário e grupo ao mesmo tempo. aluno, secretaria e coordenacao são grupos: recebem as permissões.
-- aluno_26000001 e aluno_26000012 são membros do grupo aluno e herdam (INHERIT) as permissões dele.
-- Roles valem para o servidor inteiro (não só para um banco), por isso o "se não existir".
-- Se o papel já existia, o ALTER ROLE desfaz qualquer atributo dado à mão (ex.: BYPASSRLS, que ignora o RLS).
-- Pertencimento: os 5 papéis saem de qualquer grupo em que foram colocados (ex.: GRANT secretaria TO aluno_26000012)
-- e os alunos entram só no grupo aluno. Funcionário de verdade colocado em secretaria ou coordenacao não é mexido.

DO $$
DECLARE
    v_papel TEXT;
    v_grupo RECORD;
BEGIN
    FOREACH v_papel IN ARRAY ARRAY['aluno', 'secretaria', 'coordenacao', 'aluno_26000001', 'aluno_26000012'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_papel) THEN
            EXECUTE format('CREATE ROLE %I', v_papel);
        END IF;
        EXECUTE format('ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT',
                       v_papel);

        FOR v_grupo IN
            SELECT g.rolname AS grupo, gr.rolname AS quem_deu
              FROM pg_auth_members am
              JOIN pg_roles g  ON g.oid  = am.roleid
              JOIN pg_roles gr ON gr.oid = am.grantor
             WHERE am.member = (SELECT oid FROM pg_roles WHERE rolname = v_papel)
        LOOP
            EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', v_grupo.grupo, v_papel, v_grupo.quem_deu);
        END LOOP;
    END LOOP;

    GRANT aluno TO aluno_26000001, aluno_26000012;
END $$;

SELECT r.rolname AS papel, r.rolcanlogin AS pode_conectar,
       COALESCE(string_agg(g.rolname, ', '), '-') AS membro_de
  FROM pg_roles r
  LEFT JOIN pg_auth_members am ON am.member = r.oid
  LEFT JOIN pg_roles g ON g.oid = am.roleid
 WHERE r.rolname IN ('aluno', 'secretaria', 'coordenacao', 'aluno_26000001', 'aluno_26000012')
 GROUP BY r.rolname, r.rolcanlogin
 ORDER BY r.rolname;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - NEGADO POR PADRÃO (REVOKE)
-- Primeiro tira tudo de todos. Depois o BLOCO 3 dá só o que cada papel precisa.
-- PUBLIC = "todo mundo", inclusive qualquer usuário criado no futuro.
-- Função nasce com EXECUTE liberado para PUBLIC no PostgreSQL: o REVOKE em FUNCTIONS fecha isso, e o
-- ALTER DEFAULT PRIVILEGES fecha também as funções que o bd2 criar daqui para frente.

-- O REVOKE na tabela tira junto as permissões dadas coluna a coluna (conferido no PostgreSQL 16).

REVOKE ALL ON SCHEMA projeto_bd2                  FROM PUBLIC, aluno, secretaria, coordenacao, aluno_26000001, aluno_26000012;
REVOKE ALL ON ALL TABLES    IN SCHEMA projeto_bd2 FROM PUBLIC, aluno, secretaria, coordenacao, aluno_26000001, aluno_26000012;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA projeto_bd2 FROM PUBLIC, aluno, secretaria, coordenacao, aluno_26000001, aluno_26000012;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA projeto_bd2 FROM PUBLIC, aluno, secretaria, coordenacao, aluno_26000001, aluno_26000012;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 3 - PERMISSÕES DE CADA PAPEL (GRANT)
-- USAGE no schema = poder "entrar" no schema e enxergar os objetos (sem isso nada funciona).

GRANT USAGE ON SCHEMA projeto_bd2 TO aluno, secretaria, coordenacao;

-- vw_oferta e vw_historico são security_invoker: rodam com as permissões de quem consulta. Por isso o papel
-- precisa de SELECT nas tabelas que elas leem, e o RLS dessas tabelas vale dentro da view.
-- vw_vagas é do dono (bd2): só conta matrículas e não mostra de quem são (ver 07_administracao_views_v1.sql).
GRANT SELECT ON vw_oferta, vw_vagas, vw_historico TO aluno, secretaria, coordenacao;
GRANT SELECT ON mv_indicadores                    TO secretaria, coordenacao;

-- Catálogo da oferta (informação pública da faculdade)
GRANT SELECT ON tb_turma, tb_disciplina, tb_periodo_letivo, tb_turma_horario, tb_sala, tb_curso
    TO aluno, secretaria, coordenacao;

-- ALUNO: professor só nome e titulação (e-mail e matrícula do professor ficam de fora: GRANT por coluna)
GRANT SELECT (id_professor, nm_professor, ds_titulacao) ON tb_professor TO aluno;
-- ALUNO: os próprios dados. O GRANT libera a tabela; o RLS (BLOCO 4) filtra as linhas.
GRANT SELECT ON tb_aluno, tb_matricula, tb_historico TO aluno;

-- SECRETARIA: opera a vida acadêmica (matricula, tranca, lança nota), mas não apaga nada
GRANT SELECT ON ALL TABLES IN SCHEMA projeto_bd2 TO secretaria;
GRANT INSERT, UPDATE ON tb_aluno, tb_historico TO secretaria;
GRANT INSERT ON tb_matricula TO secretaria;
GRANT UPDATE (ds_status) ON tb_matricula TO secretaria;     -- na matrícula só o status muda
-- O gatilho de auditoria roda com o usuário que alterou a matrícula, então a secretaria precisa de INSERT no log.
-- GRANT por coluna: ela não informa nm_usuario nem dt_ocorrencia, que vêm do DEFAULT (CURRENT_USER e
-- CURRENT_TIMESTAMP). Assim ninguém grava o log em nome de outra pessoa nem com outra data.
-- E o INSERT só vale vindo do gatilho: INSERT direto é recusado pelo trg_log_so_pelo_gatilho
-- (08_administracao_auditoria_v1.sql), então ninguém inventa uma linha de log.
GRANT INSERT (id_matricula, ds_acao, ds_detalhe) ON tb_log_matricula TO secretaria;

-- COORDENAÇÃO: acompanha indicadores e históricos, não altera nada.
-- Aluno sem CPF, e-mail e data de nascimento: a coordenação não precisa de dado pessoal (LGPD, minimização).
GRANT SELECT (id_aluno, cd_matricula, nm_aluno, id_curso, id_curriculo, dt_ingresso, ic_ativo)
    ON tb_aluno TO coordenacao;
GRANT SELECT ON tb_matricula, tb_historico, tb_log_matricula, tb_professor, tb_curriculo,
                tb_curriculo_disciplina, tb_pre_requisito TO coordenacao;
-- A coordenação dispara a atualização dos indicadores depois de fechar as notas (ver BLOCO 4 das views)
GRANT EXECUTE ON FUNCTION fn_atualizar_indicadores() TO coordenacao;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 4 - RLS (ROW LEVEL SECURITY)
-- ENABLE liga o RLS na tabela: a partir daí, para quem não é dono nem superusuário, só aparecem as linhas que
-- alguma policy libera (sem policy para o papel = nenhuma linha).
-- FORCE faz o RLS valer também para o dono da tabela (superusuário continua passando por cima).
-- Uma policy diz: PARA qual comando (SELECT, INSERT...), PARA qual papel (TO) e QUAIS linhas (USING / WITH CHECK).
--   USING      = quais linhas existentes o papel enxerga (SELECT, UPDATE, DELETE)
--   WITH CHECK = quais linhas o papel pode gravar (INSERT, UPDATE)

-- Matrícula do aluno conectado: o usuário aluno_26000012 vira '26000012'. Quem não é aluno recebe NULL, e
-- "cd_matricula = NULL" nunca é verdadeiro: nenhuma linha.
-- STABLE: o resultado não muda dentro da mesma consulta, então o banco calcula uma vez só e usa o índice único
-- de cd_matricula (não precisa olhar aluno por aluno).
CREATE OR REPLACE FUNCTION fn_matricula_do_usuario() RETURNS VARCHAR
LANGUAGE sql STABLE SET search_path = projeto_bd2, pg_temp AS $$
    SELECT CASE WHEN current_user::text ~ '^aluno_[0-9]+$' THEN substr(current_user::text, 7) END
$$;
REVOKE ALL ON FUNCTION fn_matricula_do_usuario() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_matricula_do_usuario() TO aluno;   -- a policy roda com o papel de quem consulta

ALTER TABLE tb_aluno     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_matricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_historico ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_aluno     FORCE  ROW LEVEL SECURITY;
ALTER TABLE tb_matricula FORCE  ROW LEVEL SECURITY;
ALTER TABLE tb_historico FORCE  ROW LEVEL SECURITY;

-- Apaga TODAS as policies das três tabelas, inclusive as que alguém criou à mão com outro nome: policies que
-- liberam linha se somam (basta uma liberar), então uma policy esquecida abriria o RLS.
DO $$
DECLARE
    v_pol RECORD;
BEGIN
    FOR v_pol IN SELECT policyname, tablename FROM pg_policies
                  WHERE schemaname = 'projeto_bd2' AND tablename IN ('tb_aluno', 'tb_matricula', 'tb_historico')
    LOOP
        EXECUTE format('DROP POLICY %I ON projeto_bd2.%I', v_pol.policyname, v_pol.tablename);
    END LOOP;
END $$;

-- tb_aluno -------------------------------------------------------------------------------------------------------------
CREATE POLICY pol_aluno_proprio_cadastro ON tb_aluno
    FOR SELECT TO aluno
    USING (cd_matricula = fn_matricula_do_usuario());

CREATE POLICY pol_secretaria_aluno ON tb_aluno
    FOR ALL TO secretaria
    USING (true) WITH CHECK (true);

CREATE POLICY pol_coordenacao_aluno ON tb_aluno
    FOR SELECT TO coordenacao
    USING (true);

-- tb_matricula ---------------------------------------------------------------------------------------------------------
CREATE POLICY pol_aluno_proprias_matriculas ON tb_matricula
    FOR SELECT TO aluno
    USING (id_aluno = (SELECT a.id_aluno FROM tb_aluno a WHERE a.cd_matricula = fn_matricula_do_usuario()));

CREATE POLICY pol_secretaria_matricula ON tb_matricula
    FOR ALL TO secretaria
    USING (true) WITH CHECK (true);

CREATE POLICY pol_coordenacao_matricula ON tb_matricula
    FOR SELECT TO coordenacao
    USING (true);

-- tb_historico ---------------------------------------------------------------------------------------------------------
-- O histórico não tem id_aluno: chega no aluno pela matrícula.
CREATE POLICY pol_aluno_proprio_historico ON tb_historico
    FOR SELECT TO aluno
    USING (id_matricula IN (SELECT m.id_matricula
                              FROM tb_matricula m
                              JOIN tb_aluno a ON a.id_aluno = m.id_aluno
                             WHERE a.cd_matricula = fn_matricula_do_usuario()));

CREATE POLICY pol_secretaria_historico ON tb_historico
    FOR ALL TO secretaria
    USING (true) WITH CHECK (true);

CREATE POLICY pol_coordenacao_historico ON tb_historico
    FOR SELECT TO coordenacao
    USING (true);


------------------------------------------------------------------------------------------------------------------------
-- CONFERÊNCIA (aba Data Output)
-- 1) tabelas com RLS ligado e quantas policies cada uma tem
SELECT c.relname AS tabela, c.relrowsecurity AS rls_ligado, c.relforcerowsecurity AS rls_forcado,
       (SELECT count(*) FROM pg_policies p WHERE p.schemaname = 'projeto_bd2' AND p.tablename = c.relname) AS policies
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'projeto_bd2' AND c.relkind = 'r' AND c.relrowsecurity
 ORDER BY c.relname;

-- 2) o que cada papel pode fazer em cada tabela e view (lido do próprio banco, não da lista de GRANT)
SELECT c.relname AS objeto, r.papel,
       CASE WHEN has_table_privilege(r.papel, c.oid, 'SELECT')      THEN 'tudo'
            WHEN has_any_column_privilege(r.papel, c.oid, 'SELECT') THEN 'algumas colunas'
            ELSE '-' END AS le,
       has_table_privilege(r.papel, c.oid, 'INSERT') AS inclui,
       has_table_privilege(r.papel, c.oid, 'UPDATE') AS altera,
       has_table_privilege(r.papel, c.oid, 'DELETE') AS apaga
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 CROSS JOIN (VALUES ('aluno'), ('secretaria'), ('coordenacao')) AS r(papel)
 WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm')
 ORDER BY c.relname, r.papel;
