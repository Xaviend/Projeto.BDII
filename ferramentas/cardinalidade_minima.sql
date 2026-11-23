-- Cardinalidade minima na carga: para cada relacionamento do modelo, quantos "pais" ficam SEM nenhum filho.
-- 0 = todo pai tem filho na carga (minima 1 no diagrama). Mais de 0 = existe caso real de pai sem filho (minima 0).
-- Usada pelo README ("Como ler a cardinalidade") e pelo rodape dos dois diagramas em modelo/.
-- Roda depois do 03_carga_v1.sql. So le.
SET search_path TO projeto_bd2, public;

SELECT caso, sem_filho, total FROM (VALUES
  (1,  'cidade sem campus',                  (SELECT count(*) FROM tb_cidade c WHERE NOT EXISTS (SELECT 1 FROM tb_campus x WHERE x.id_cidade = c.id_cidade)), (SELECT count(*) FROM tb_cidade)),
  (2,  'campus sem curso',                   (SELECT count(*) FROM tb_campus c WHERE NOT EXISTS (SELECT 1 FROM tb_curso x WHERE x.id_campus = c.id_campus)), (SELECT count(*) FROM tb_campus)),
  (3,  'campus sem sala',                    (SELECT count(*) FROM tb_campus c WHERE NOT EXISTS (SELECT 1 FROM tb_sala x WHERE x.id_campus = c.id_campus)), (SELECT count(*) FROM tb_campus)),
  (4,  'campus sem feriado local',           (SELECT count(*) FROM tb_campus c WHERE NOT EXISTS (SELECT 1 FROM tb_feriado x WHERE x.id_campus = c.id_campus)), (SELECT count(*) FROM tb_campus)),
  (5,  'feriado sem campus (nacional)',      (SELECT count(*) FROM tb_feriado WHERE id_campus IS NULL), (SELECT count(*) FROM tb_feriado)),
  (6,  'curso sem curriculo',                (SELECT count(*) FROM tb_curso c WHERE NOT EXISTS (SELECT 1 FROM tb_curriculo x WHERE x.id_curso = c.id_curso)), (SELECT count(*) FROM tb_curso)),
  (7,  'curso sem aluno',                    (SELECT count(*) FROM tb_curso c WHERE NOT EXISTS (SELECT 1 FROM tb_aluno x WHERE x.id_curso = c.id_curso)), (SELECT count(*) FROM tb_curso)),
  (8,  'curriculo sem disciplina',           (SELECT count(*) FROM tb_curriculo c WHERE NOT EXISTS (SELECT 1 FROM tb_curriculo_disciplina x WHERE x.id_curriculo = c.id_curriculo)), (SELECT count(*) FROM tb_curriculo)),
  (9,  'curriculo sem aluno',                (SELECT count(*) FROM tb_curriculo c WHERE NOT EXISTS (SELECT 1 FROM tb_aluno x WHERE x.id_curriculo = c.id_curriculo)), (SELECT count(*) FROM tb_curriculo)),
  (10, 'disciplina fora de grade',           (SELECT count(*) FROM tb_disciplina d WHERE NOT EXISTS (SELECT 1 FROM tb_curriculo_disciplina x WHERE x.id_disciplina = d.id_disciplina)), (SELECT count(*) FROM tb_disciplina)),
  (11, 'disciplina sem pre-requisito',       (SELECT count(*) FROM tb_disciplina d WHERE NOT EXISTS (SELECT 1 FROM tb_pre_requisito x WHERE x.id_disciplina = d.id_disciplina)), (SELECT count(*) FROM tb_disciplina)),
  (12, 'disciplina que nao e pre-requisito', (SELECT count(*) FROM tb_disciplina d WHERE NOT EXISTS (SELECT 1 FROM tb_pre_requisito x WHERE x.id_disciplina_requisito = d.id_disciplina)), (SELECT count(*) FROM tb_disciplina)),
  (13, 'disciplina sem turma',               (SELECT count(*) FROM tb_disciplina d WHERE NOT EXISTS (SELECT 1 FROM tb_turma x WHERE x.id_disciplina = d.id_disciplina)), (SELECT count(*) FROM tb_disciplina)),
  (14, 'periodo letivo sem turma',           (SELECT count(*) FROM tb_periodo_letivo p WHERE NOT EXISTS (SELECT 1 FROM tb_turma x WHERE x.id_periodo_letivo = p.id_periodo_letivo)), (SELECT count(*) FROM tb_periodo_letivo)),
  (15, 'periodo letivo sem horario',         (SELECT count(*) FROM tb_periodo_letivo p WHERE NOT EXISTS (SELECT 1 FROM tb_turma_horario x WHERE x.id_periodo_letivo = p.id_periodo_letivo)), (SELECT count(*) FROM tb_periodo_letivo)),
  (16, 'professor sem turma',                (SELECT count(*) FROM tb_professor p WHERE NOT EXISTS (SELECT 1 FROM tb_turma x WHERE x.id_professor = p.id_professor)), (SELECT count(*) FROM tb_professor)),
  (17, 'turma sem horario',                  (SELECT count(*) FROM tb_turma t WHERE NOT EXISTS (SELECT 1 FROM tb_turma_horario x WHERE x.id_turma = t.id_turma)), (SELECT count(*) FROM tb_turma)),
  (18, 'sala sem horario',                   (SELECT count(*) FROM tb_sala s WHERE NOT EXISTS (SELECT 1 FROM tb_turma_horario x WHERE x.id_sala = s.id_sala)), (SELECT count(*) FROM tb_sala)),
  (19, 'aluno sem matricula',                (SELECT count(*) FROM tb_aluno a WHERE NOT EXISTS (SELECT 1 FROM tb_matricula x WHERE x.id_aluno = a.id_aluno)), (SELECT count(*) FROM tb_aluno)),
  (20, 'turma sem matricula',                (SELECT count(*) FROM tb_turma t WHERE NOT EXISTS (SELECT 1 FROM tb_matricula x WHERE x.id_turma = t.id_turma)), (SELECT count(*) FROM tb_turma)),
  (21, 'matricula sem historico',            (SELECT count(*) FROM tb_matricula m WHERE NOT EXISTS (SELECT 1 FROM tb_historico x WHERE x.id_matricula = m.id_matricula)), (SELECT count(*) FROM tb_matricula))
) AS v (ordem, caso, sem_filho, total)
ORDER BY ordem;

-- Detalhe dos casos com minima 0
SELECT 'sala sem horario' AS caso, s.cd_sala || ' (' || s.ds_tipo || ')' AS quem
  FROM tb_sala s WHERE NOT EXISTS (SELECT 1 FROM tb_turma_horario x WHERE x.id_sala = s.id_sala)
UNION ALL
SELECT 'campus sem curso', c.nm_campus
  FROM tb_campus c WHERE NOT EXISTS (SELECT 1 FROM tb_curso x WHERE x.id_campus = c.id_campus)
UNION ALL
SELECT 'matricula sem historico, por status', m.ds_status || ': ' || count(*)
  FROM tb_matricula m WHERE NOT EXISTS (SELECT 1 FROM tb_historico x WHERE x.id_matricula = m.id_matricula)
 GROUP BY m.ds_status
ORDER BY 1, 2;
