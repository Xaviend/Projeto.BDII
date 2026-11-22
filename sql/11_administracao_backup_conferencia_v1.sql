/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: "impressão digital" do banco para provar que o backup restaurado é IGUAL ao original.
          Rode ANTES do backup e DEPOIS da restauração: se as duas saídas forem iguais, nada se perdeu.
          O passo a passo do backup e da restauração está em docs/backup_restauracao.md.

O que a impressão digital confere:
  1) cada tabela e a materialized view: quantidade de linhas e um md5 (código de 32 letras calculado a partir do
     conteúdo de todas as linhas). Mudou uma nota em uma linha, o md5 muda inteiro;
  2) a estrutura: views, índices, policies de RLS, gatilhos, funções e permissões;
  3) uma linha final que resume tudo num md5 só (é a que se compara na apresentação).

Detalhe: a coluna dt_atualizacao da mv_indicadores fica fora do md5. A restauração recalcula a materialized view
(REFRESH) e essa coluna guarda a hora do cálculo, então ela muda sempre, mesmo com os dados iguais.

Como rodar: F5 com o usuário bd2 (superusuário: enxerga todas as linhas, sem o filtro do RLS).
            Pode rodar quantas vezes quiser: não altera nada.

11_administracao_backup_conferencia_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula, ou matricula_restaurada no teste de restauração)
SELECT current_database();
SET search_path TO projeto_bd2, public;

CREATE OR REPLACE FUNCTION pg_temp.fn_impressao_digital()
RETURNS TABLE (item TEXT, linhas BIGINT, md5 TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_objeto RECORD;
BEGIN
    -- 1) dados: uma linha por tabela e materialized view
    FOR v_objeto IN
        SELECT c.relname
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'm')
         ORDER BY c.relname
    LOOP
        RETURN QUERY EXECUTE format(
            $q$SELECT %L::text, count(*),
                      md5(COALESCE(string_agg((to_jsonb(t) - 'dt_atualizacao')::text, '|'
                                              ORDER BY (to_jsonb(t) - 'dt_atualizacao')::text), ''))
                 FROM projeto_bd2.%I t$q$,
            'dados: ' || v_objeto.relname, v_objeto.relname);
    END LOOP;

    -- 2) estrutura
    RETURN QUERY
    SELECT 'estrutura: views e materialized views', count(*),
           md5(COALESCE(string_agg(c.relname || '=' || pg_get_viewdef(c.oid) || COALESCE(c.reloptions::text, ''),
                                   '|' ORDER BY c.relname), ''))
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('v', 'm');

    RETURN QUERY
    SELECT 'estrutura: indices', count(*),
           md5(COALESCE(string_agg(indexname || '=' || indexdef, '|' ORDER BY indexname), ''))
      FROM pg_indexes WHERE schemaname = 'projeto_bd2';

    RETURN QUERY
    SELECT 'estrutura: policies de RLS', count(*),
           md5(COALESCE(string_agg(tablename || '.' || policyname || '=' || cmd || ':' || roles::text || ':'
                                   || COALESCE(qual, '') || ':' || COALESCE(with_check, ''),
                                   '|' ORDER BY tablename, policyname), ''))
      FROM pg_policies WHERE schemaname = 'projeto_bd2';

    RETURN QUERY
    SELECT 'estrutura: tabelas com RLS ligado e forcado', count(*),
           md5(COALESCE(string_agg(c.relname, '|' ORDER BY c.relname), ''))
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'projeto_bd2' AND c.relrowsecurity AND c.relforcerowsecurity;

    RETURN QUERY
    SELECT 'estrutura: gatilhos', count(*),
           md5(COALESCE(string_agg(pg_get_triggerdef(t.oid), '|' ORDER BY t.tgname), ''))
      FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'projeto_bd2' AND NOT t.tgisinternal;

    RETURN QUERY
    SELECT 'estrutura: funcoes e quem pode executar', count(*),
           md5(COALESCE(string_agg(pg_get_functiondef(p.oid)
                                   || (SELECT string_agg(CASE WHEN e.grantee = 0 THEN 'PUBLIC'
                                                              ELSE pg_get_userbyid(e.grantee) END, ',' ORDER BY 1)
                                         FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) e),
                                   '|' ORDER BY p.proname), ''))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'projeto_bd2';

    -- Permissão efetiva, uma linha por (objeto, papel, privilégio). Compara o que vale, e não o texto guardado:
    -- o pg_dump não grava a permissão que é igual ao padrão, então o texto muda e a permissão não.
    RETURN QUERY
    SELECT 'estrutura: permissoes (GRANT) em tabelas, colunas e schema', count(*),
           md5(COALESCE(string_agg(x, '|' ORDER BY x), ''))
      FROM (SELECT c.relname || ':' || CASE WHEN p.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(p.grantee) END
                   || ':' || p.privilege_type AS x
              FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,
                                acldefault(CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END::"char", c.relowner))) p
             WHERE n.nspname = 'projeto_bd2' AND c.relkind IN ('r', 'v', 'm', 'S')
            UNION ALL
            SELECT c.relname || '.' || a.attname || ':'
                   || CASE WHEN p.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(p.grantee) END || ':' || p.privilege_type
              FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
              JOIN pg_namespace n ON n.oid = c.relnamespace
             CROSS JOIN LATERAL aclexplode(a.attacl) p
             WHERE n.nspname = 'projeto_bd2' AND a.attacl IS NOT NULL
            UNION ALL
            SELECT 'schema:' || CASE WHEN p.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(p.grantee) END
                   || ':' || p.privilege_type
              FROM pg_namespace s
             CROSS JOIN LATERAL aclexplode(COALESCE(s.nspacl, acldefault('n', s.nspowner))) p
             WHERE s.nspname = 'projeto_bd2') s;
END $$;

-- Resultado (aba Data Output): as linhas de cada item e, por último, o resumo de tudo
WITH digital AS (SELECT * FROM pg_temp.fn_impressao_digital())
SELECT item, linhas, md5
  FROM (SELECT 1 AS ordem, item, linhas, md5 FROM digital
        UNION ALL
        SELECT 2, '>>> IMPRESSAO DIGITAL GERAL (compare esta)', sum(linhas)::bigint,
               md5(string_agg(item || ':' || linhas || ':' || md5, '|' ORDER BY item))
          FROM digital) r
 ORDER BY ordem, item;
