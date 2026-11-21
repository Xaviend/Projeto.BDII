/*
Autor: Eduardo Serra - Transações e Concorrência
Objetivo: desfazer os testes da última vaga (apaga as matrículas dos alunos 26000001 e 26000002 na turma alvo)
          e deixar a turma de novo com exatamente 1 vaga livre.

Como usar: rodar numa aba só, DEPOIS de dar COMMIT ou ROLLBACK nas duas abas dos testes.
Se alguma aba ainda tiver transação aberta o script dá erro: rodar ROLLBACK nela e tentar de novo.
(o DELETE não enxerga matrícula que ainda não teve COMMIT, então ela ficaria lá e o próximo teste começaria errado)
Pode rodar quantas vezes quiser.
*/
------------------------------------------------------------------------------------------------------------------------
SET search_path TO projeto_bd2, public;

-- confere se não tem outra aba com transação aberta
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_stat_activity
                WHERE datname = current_database()
                  AND pid <> pg_backend_pid()
                  AND (state LIKE 'idle in transaction%' OR wait_event_type = 'Lock')) THEN
        RAISE EXCEPTION 'tem aba com transacao aberta, dar ROLLBACK nela antes da limpeza';
    END IF;
END $$;

DELETE FROM projeto_bd2.tb_matricula
 WHERE id_aluno IN (SELECT id_aluno FROM projeto_bd2.tb_aluno WHERE cd_matricula IN ('26000001', '26000002'))
   AND id_turma = (SELECT t.id_turma
                     FROM projeto_bd2.tb_turma t
                     JOIN projeto_bd2.tb_disciplina d     ON d.id_disciplina = t.id_disciplina
                     JOIN projeto_bd2.tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
                    WHERE d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2
                      AND t.cd_turma = 'A');

-- Conferência (esperado: ocupadas = 34, vagas_livres = 1)
SELECT t.qt_vagas, count(m.id_matricula) AS ocupadas, t.qt_vagas - count(m.id_matricula) AS vagas_livres
  FROM projeto_bd2.tb_turma t
  JOIN projeto_bd2.tb_disciplina d     ON d.id_disciplina = t.id_disciplina AND d.cd_disciplina = 'CCO072'
  JOIN projeto_bd2.tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo AND p.aa_periodo = 2026 AND p.cd_semestre = 2
  LEFT JOIN projeto_bd2.tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
 WHERE t.cd_turma = 'A'
 GROUP BY t.qt_vagas;
