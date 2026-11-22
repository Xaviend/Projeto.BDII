/*
Autor: Eduardo Serra - Transações e Concorrência
Objetivo: REPRODUZIR O ERRO. Dois alunos pegam a última vaga ao mesmo tempo e a turma estoura (46 ativas para 45 vagas).

Por que acontece: o isolamento padrão do PostgreSQL é READ COMMITTED. Cada sessão só enxerga o que já foi confirmado
(COMMIT) por outras. As duas contam as vagas ANTES de qualquer uma confirmar, as duas veem "1 livre" e as duas inserem.
A regra "não passar das vagas" está só na cabeça da aplicação (conferir e inserir são dois passos), o banco não a impõe.

Como usar:
  - rodar 05e_concorrencia_limpeza_v1.sql e 05a_concorrencia_preparacao_v1.sql nas DUAS abas antes;
  - rodar cada passo SÓ na aba indicada, na ordem dos números;
  - no pgAdmin, selecione o trecho do passo e aperte F5 (sem selecionar, ele roda o arquivo todo);
  - tirar print do passo 2 e do passo 5 (vagas_livres = -1) e salvar em evidencias/.
*/
------------------------------------------------------------------------------------------------------------------------
SET search_path TO projeto_bd2, public;   -- (as duas abas)

-- PASSO 1 - ABA 1: abre a transação e confere a vaga (vê vagas_livres = 1)
BEGIN;
SELECT t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.qt_vagas;

-- PASSO 2 - ABA 2: abre a transação e confere a vaga (TAMBÉM vê vagas_livres = 1)
BEGIN;
SELECT t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.qt_vagas;

-- PASSO 3 - ABA 1: matricula o aluno A e confirma (tem que aparecer INSERT 0 1)
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT id_aluno, current_setting('projeto_bd2.turma_alvo')::int, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno WHERE cd_matricula = current_setting('projeto_bd2.aluno_a');
COMMIT;

-- PASSO 4 - ABA 2: ainda "acha" que tem vaga (leu no passo 2), matricula o aluno B e confirma
-- (tem que aparecer INSERT 0 1, se vier INSERT 0 0 o aluno não existe na carga)
INSERT INTO projeto_bd2.tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT id_aluno, current_setting('projeto_bd2.turma_alvo')::int, now(), 'ativa'::projeto_bd2.tp_status_matricula
  FROM projeto_bd2.tb_aluno WHERE cd_matricula = current_setting('projeto_bd2.aluno_b');
COMMIT;

-- PASSO 5 - qualquer aba: PROVA DO ERRO (esperado: ocupadas = 36, vagas_livres = -1)
SELECT t.qt_vagas, count(m.id_matricula) AS ocupadas, t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.qt_vagas;

-- PASSO 6 - antes de testar as soluções: rodar 05e_concorrencia_limpeza_v1.sql
