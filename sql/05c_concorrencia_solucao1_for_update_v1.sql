/*
Autor: Eduardo Serra - Transações e Concorrência
Objetivo: SOLUÇÃO 1 - bloqueio pessimista com SELECT ... FOR UPDATE na linha da turma.

Ideia: quem chega primeiro "tranca" a linha da turma. O segundo espera, na fila, até o primeiro dar COMMIT/ROLLBACK.
Quando destrava, o segundo conta as vagas DE NOVO (no READ COMMITTED cada comando enxerga o que já foi confirmado),
vê a turma cheia e não insere. Conferir e inserir passam a ser um passo protegido, sem "janela" entre os dois.

As duas abas usam o mesmo INSERT, que só insere se ainda tiver vaga. A ABA 1 insere e a ABA 2 não (INSERT 0 0).
Sem o FOR UPDATE esse INSERT não resolve sozinho: se as duas inserirem antes de algum COMMIT, as duas contam 44.

Como usar:
  - rodar 05e_concorrencia_limpeza_v1.sql e 05a_concorrencia_preparacao_v1.sql nas DUAS abas antes (vagas_livres = 1);
  - rodar cada passo SÓ na aba indicada, na ordem dos números (selecione o trecho e F5);
  - tirar print do passo 3 (a aba "executando", travada), do passo 5 (INSERT 0 0) e do passo 6 (vagas_livres = 0).
*/
------------------------------------------------------------------------------------------------------------------------
SET search_path TO projeto_bd2, public;   -- (as duas abas)

-- PASSO 1 - ABA 1: abre a transação e TRANCA a turma
BEGIN;
SELECT id_turma, qt_vagas FROM projeto_bd2.tb_turma
 WHERE id_turma = current_setting('projeto_bd2.turma_alvo')::int
   FOR UPDATE;

-- PASSO 2 - ABA 1: matricula o aluno A se tiver vaga (INSERT 0 1). NÃO dê COMMIT ainda.
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT a.id_aluno, t.id_turma, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno a, projeto_bd2.tb_turma t
 WHERE a.cd_matricula = current_setting('projeto_bd2.aluno_a')
   AND t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
   AND t.qt_vagas > (SELECT count(*) FROM projeto_bd2.tb_matricula m
                      WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa');

-- PASSO 3 - ABA 2: tenta trancar a mesma turma. A aba FICA TRAVADA esperando (tire o print agora).
BEGIN;
SELECT id_turma, qt_vagas FROM projeto_bd2.tb_turma
 WHERE id_turma = current_setting('projeto_bd2.turma_alvo')::int
   FOR UPDATE;

-- PASSO 4 - ABA 1: confirma e libera a turma
COMMIT;

-- PASSO 5 - ABA 2: o passo 3 destravou sozinho. Mesmo INSERT do passo 2 com o aluno B: turma cheia, INSERT 0 0.
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

-- Depois: rodar 05e_concorrencia_limpeza_v1.sql
