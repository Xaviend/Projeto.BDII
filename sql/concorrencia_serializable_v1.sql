/*
Autor: Eduardo Serra - Transações e Concorrência
Objetivo: SOLUÇÃO 2 - nível de isolamento SERIALIZABLE (abordagem otimista: ninguém espera, o banco aborta um dos dois).

Ideia: no SERIALIZABLE o PostgreSQL garante que o resultado de transações simultâneas seja igual ao de alguma execução
UMA DEPOIS DA OUTRA. Ele percebe que as duas leram a contagem de vagas e depois inseriram linhas que mudariam essa
contagem (dependência de leitura/escrita), e derruba uma delas com o erro 40001 (serialization_failure).
A aplicação precisa REPETIR a transação derrubada (retry). Na repetição ela vê a turma cheia e não insere.

As duas abas usam o mesmo INSERT do 05c (só insere se ainda tiver vaga), então ninguém decide nada na mão.
obs: só protege se TODAS as transações de matrícula rodarem em SERIALIZABLE.

Como usar:
  - rodar 05e_concorrencia_limpeza.sql e 05a_concorrencia_preparacao.sql nas DUAS abas antes (vagas_livres = 1);
  - rodar cada passo SÓ na aba indicada, na ordem dos números (selecione o trecho e F5);
  - tirar print do erro do passo 3 (SQLSTATE 40001), do passo 5 (INSERT 0 0) e da prova do passo 6.
*/
------------------------------------------------------------------------------------------------------------------------
SET search_path TO projeto_bd2, public;   -- (as duas abas)

-- PASSO 1 - ABA 1 e depois ABA 2: abre transação SERIALIZABLE e confere a vaga (as duas veem 1 livre)
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.qt_vagas;

-- PASSO 2 - ABA 1: matricula o aluno A se tiver vaga e confirma (INSERT 0 1, funciona)
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT a.id_aluno, t.id_turma, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno a, projeto_bd2.tb_turma t
 WHERE a.cd_matricula = current_setting('projeto_bd2.aluno_a')
   AND t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
   AND t.qt_vagas > (SELECT count(*) FROM projeto_bd2.tb_matricula m
                      WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa');
COMMIT;

-- PASSO 3 - ABA 2: mesmo INSERT com o aluno B. ERRO ESPERADO aqui (tire o print):
--   ERROR: could not serialize access due to read/write dependencies among transactions
--   SQLSTATE 40001
-- o erro pode aparecer no INSERT ou no COMMIT, nos dois casos é o comportamento esperado
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT a.id_aluno, t.id_turma, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno a, projeto_bd2.tb_turma t
 WHERE a.cd_matricula = current_setting('projeto_bd2.aluno_b')
   AND t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
   AND t.qt_vagas > (SELECT count(*) FROM projeto_bd2.tb_matricula m
                      WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa');
COMMIT;

-- PASSO 4 - ABA 2: encerra a transação que falhou
-- (se o erro veio no COMMIT a transação já acabou e aparece o aviso "there is no transaction in progress", é normal)
ROLLBACK;

-- PASSO 5 - ABA 2: RETRY. Refaz tudo do zero com o mesmo INSERT: agora a turma está cheia (INSERT 0 0)
BEGIN ISOLATION LEVEL SERIALIZABLE;
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT a.id_aluno, t.id_turma, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno a, projeto_bd2.tb_turma t
 WHERE a.cd_matricula = current_setting('projeto_bd2.aluno_b')
   AND t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
   AND t.qt_vagas > (SELECT count(*) FROM projeto_bd2.tb_matricula m
                      WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa');
COMMIT;   -- não inseriu nada: aluno B fica sem a vaga, mas a turma não estoura

-- PASSO 6 - qualquer aba: PROVA (esperado: ocupadas = 35, vagas_livres = 0)
SELECT t.qt_vagas, count(m.id_matricula) AS ocupadas, t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.qt_vagas;

-- Depois: rodar 05e_concorrencia_limpeza.sql
