/*
Autor: Eduardo Serra - Transações e Concorrência
Objetivo: preparar a demonstração da "última vaga" (CCO072 / 2026-2 / seção A) e conferir quantas vagas livres existem.

Como usar:
  - abrir DUAS abas de Query Tool no pgAdmin (ABA 1 e ABA 2), as duas no banco matricula;
  - rodar ESTE arquivo inteiro (F5) nas DUAS abas: os parâmetros abaixo valem só para a sessão (aba) onde foram criados;
  - rodar depois de 01_modelo_fisico_v1.sql e 03_carga_v1.sql (o 04_indices_v1.sql não é obrigatório, mas as
    evidências foram geradas com os índices criados);
  - se der erro, ler a mensagem na aba Mensagens (banco errado, schema não criado ou turma não encontrada);
  - o bloco 2 (conferência) pode ser rodado de novo a qualquer momento para ver as vagas livres.

Alunos da demonstração: 26000001 (ABA 1) e 26000002 (ABA 2). São do 1º semestre, não estão nessa turma.
*/
------------------------------------------------------------------------------------------------------------------------
SET search_path TO projeto_bd2, public;

------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - CONFERE O BANCO E GUARDA OS PARÂMETROS DA SESSÃO
-- obs: no F5 o pgAdmin só mostra o resultado do último comando, por isso a conferência dá erro em vez de SELECT
DO $$
DECLARE
    v_turma integer;
BEGIN
    IF current_database() <> 'matricula' THEN
        RAISE EXCEPTION 'banco errado: % (tem que ser matricula)', current_database();
    END IF;

    IF to_regclass('projeto_bd2.tb_turma') IS NULL THEN
        RAISE EXCEPTION 'schema projeto_bd2 nao existe, rodar modelo fisico, carga e indices antes';
    END IF;

    -- turma alvo: Banco de Dados II (CCO072), 2026/2, seção A (a carga deixou ela com 1 vaga livre)
    SELECT t.id_turma INTO v_turma
      FROM projeto_bd2.tb_turma t
      JOIN projeto_bd2.tb_disciplina d     ON d.id_disciplina = t.id_disciplina
      JOIN projeto_bd2.tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
     WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2
       AND t.cd_turma = 'A';

    IF v_turma IS NULL THEN
        RAISE EXCEPTION 'turma CCO072 2026/2 A nao encontrada, conferir a carga';
    END IF;

    PERFORM set_config('projeto_bd2.turma_alvo', v_turma::text, false);
    PERFORM set_config('projeto_bd2.aluno_a', '26000001', false);
    PERFORM set_config('projeto_bd2.aluno_b', '26000002', false);

    RAISE NOTICE 'ok, turma_alvo = %', v_turma;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - CONFERÊNCIA DAS VAGAS (esperado antes de cada teste: vagas_livres = 1)
SELECT t.id_turma, t.qt_vagas,
       count(m.id_matricula)              AS ocupadas,
       t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.id_turma = current_setting('projeto_bd2.turma_alvo')::int
 GROUP BY t.id_turma, t.qt_vagas;
