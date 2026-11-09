/*
Autor: Iury Xavier Bomfim  - Modelagem Física e Desempenho
Objetivo: provar que as restrições do modelo_fisico_v1.sql funcionam. Para cada regra:
          1 INSERT que PASSA (dado válido) e 1 que é BARRADO (dado inválido).

Como funciona:
  - tudo roda dentro de BEGIN ... ROLLBACK: no fim, nada fica gravado no banco;
  - cada teste negativo fica dentro de um bloco DO que CAPTURA o erro esperado e mostra
    "OK barrado: <mensagem do banco>" na aba Messages do pgAdmin;
  - se um teste negativo NÃO der erro, o bloco solta "FALHOU" e o script para: aí tem restrição faltando.
  Então o script roda inteiro com F5, e é só ler a aba Messages.

Resultado esperado: 14 linhas "OK barrado (...)" e nenhuma "FALHOU".

testes_restricoes_v1
*/
------------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

BEGIN;

------------------------------------------------------------------------------------------------------------------------------
--BLOCO 1 - DOMÍNIOS E TIPOS

-- PASSA: 7,5 é uma nota válida no domínio dm_nota
SELECT 7.5::dm_nota AS nota_valida;

-- BARRADO: 10,5 passa do limite do domínio (0 a 10)
DO $$ BEGIN
    PERFORM 10.5::dm_nota;
    RAISE EXCEPTION 'FALHOU: dm_nota aceitou 10.5';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 1): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 2 - CIDADE, CAMPUS E FERIADO

-- PASSA
INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('Cidade Teste', 'DF');
INSERT INTO tb_campus (nm_campus, id_cidade)
VALUES ('Campus Teste', (SELECT id_cidade FROM tb_cidade WHERE nm_cidade = 'Cidade Teste'));
INSERT INTO tb_feriado (dt_feriado, ds_feriado) VALUES ('2099-11-15', 'Feriado nacional teste'); -- id_campus NULL = nacional

-- BARRADO: segundo feriado NACIONAL no mesmo dia (UNIQUE NULLS NOT DISTINCT)
DO $$ BEGIN
    INSERT INTO tb_feriado (dt_feriado, ds_feriado) VALUES ('2099-11-15', 'Duplicado');
    RAISE EXCEPTION 'FALHOU: aceitou 2 feriados nacionais no mesmo dia';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK barrado (bloco 2): %', SQLERRM;
END $$;

-- BARRADO: cidade com nome só de espaços (NOT NULL sozinho deixaria passar)
DO $$ BEGIN
    INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('   ', 'DF');
    RAISE EXCEPTION 'FALHOU: aceitou cidade sem nome';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 2b): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 3 - CURSO, CURRÍCULO E DISCIPLINA

-- PASSA (a qt_ch_total é calculada pelo banco: 40 + 40 = 80)
INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
VALUES ('TST1', 'Curso Teste 1', 'bacharelado', 3200, (SELECT id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste')),
       ('TST2', 'Curso Teste 2', 'tecnologo',   2000, (SELECT id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste'));
INSERT INTO tb_curriculo (id_curso, aa_vigencia)
SELECT id_curso, 2026 FROM tb_curso WHERE cd_curso IN ('TST1', 'TST2');
INSERT INTO tb_disciplina (cd_disciplina, nm_disciplina, qt_ch_teorica, qt_ch_pratica)
VALUES ('TSTBD1', 'BD Teste 1', 40, 40),
       ('TSTBD2', 'BD Teste 2', 40, 40);
SELECT cd_disciplina, qt_ch_total FROM tb_disciplina WHERE cd_disciplina LIKE 'TST%';  -- esperado: 80 e 80

-- BARRADO: disciplina sem nenhuma carga horária (CHECK)
DO $$ BEGIN
    INSERT INTO tb_disciplina (cd_disciplina, nm_disciplina, qt_ch_teorica, qt_ch_pratica)
    VALUES ('TSTZERO', 'Sem carga', 0, 0);
    RAISE EXCEPTION 'FALHOU: aceitou disciplina com carga 0';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 3): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 4 - CURRÍCULO x DISCIPLINA E PRÉ-REQUISITO

-- PASSA: BD Teste 2 exige BD Teste 1
INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade)
VALUES ((SELECT c.id_curriculo FROM tb_curriculo c JOIN tb_curso u USING (id_curso) WHERE u.cd_curso = 'TST1'),
        (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'), 3);
INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
VALUES ((SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD2'),
        (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'));

-- BARRADO: disciplina como pré-requisito dela mesma (CHECK)
DO $$ BEGIN
    INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
    SELECT id_disciplina, id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1';
    RAISE EXCEPTION 'FALHOU: aceitou disciplina como pré-requisito de si mesma';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 4): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 5 - PROFESSOR, PERÍODO LETIVO E SALA

-- PASSA
INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
VALUES ('TSTP1', 'Professor Teste', 'prof.teste@iesb.br', 'mestre');
INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
VALUES (2099, 1, '2099-02-01', '2099-06-30'),
       (2099, 2, '2099-08-01', '2099-12-15');
INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo)
VALUES ((SELECT id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste'), 'T101', 40, 'laboratorio');

-- BARRADO: semestre 3 não existe (CHECK cd_semestre IN (1,2))
DO $$ BEGIN
    INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
    VALUES (2099, 3, '2099-01-01', '2099-06-30');
    RAISE EXCEPTION 'FALHOU: aceitou semestre 3';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 5): %', SQLERRM;
END $$;

-- BARRADO: período "2098/1" com datas de 1980 (ano das datas não bate com aa_periodo)
DO $$ BEGIN
    INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
    VALUES (2098, 1, '1980-01-01', '1980-01-02');
    RAISE EXCEPTION 'FALHOU: aceitou período com ano errado';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 5b): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 6 - TURMA E HORÁRIO

-- PASSA: turma em 2099/2 na sala T101, segunda-feira, das 19:00 às 20:40
INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
VALUES ('TSTTURMA',
        (SELECT id_disciplina     FROM tb_disciplina     WHERE cd_disciplina = 'TSTBD2'),
        (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
        (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
        'noturno', 40);
INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
SELECT t.id_turma, t.id_periodo_letivo, s.id_sala, 1, '19:00', '20:40'
  FROM tb_turma t, tb_sala s
 WHERE t.cd_turma = 'TSTTURMA' AND s.cd_sala = 'T101';

-- PASSA: MESMA sala, MESMO dia e horário, mas em OUTRO semestre (2099/1). Antes da correção isto era barrado.
INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
VALUES ('TSTTURMA',
        (SELECT id_disciplina     FROM tb_disciplina     WHERE cd_disciplina = 'TSTBD2'),
        (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 1),
        (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
        'noturno', 40);
INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
SELECT t.id_turma, t.id_periodo_letivo, s.id_sala, 1, '19:00', '20:40'
  FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_sala s
 WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 1 AND s.cd_sala = 'T101';
SELECT COUNT(*) AS horarios_na_t101 FROM tb_turma_horario;   -- esperado: 2

-- BARRADO: mesma sala, mesmo dia, 20:00 às 21:40 (se sobrepõe com 19:00-20:40) -> EXCLUDE
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, t.id_periodo_letivo, s.id_sala, 1, '20:00', '21:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou choque de horário na mesma sala';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'OK barrado (bloco 6): %', SQLERRM;
END $$;

-- BARRADO: horário dizendo que a turma de 2099/2 é de 2099/1 (FK composta não deixa divergir)
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, p1.id_periodo_letivo, s.id_sala, 3, '08:00', '09:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_periodo_letivo p1, tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2
       AND p1.aa_periodo = 2099 AND p1.cd_semestre = 1 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou horário com semestre diferente do da turma';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'OK barrado (bloco 6b): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 7 - ALUNO, MATRÍCULA, HISTÓRICO E LOG

-- PASSA: aluno do curso TST1 com o currículo do TST1; nota A1=6, A2=7, P3=9
-- média esperada: maior entre 0,4*6+0,6*7=6,60 | 0,4*9+0,6*7=7,80 | 0,4*6+0,6*9=7,80  -> 7,80 (aprovado)
INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
SELECT 'TSTA1', 'Aluno Teste', '00000000191', 'aluno.teste@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
  FROM tb_curso u JOIN tb_curriculo c USING (id_curso)
 WHERE u.cd_curso = 'TST1';
INSERT INTO tb_matricula (id_aluno, id_turma)
VALUES ((SELECT id_aluno FROM tb_aluno WHERE cd_matricula = 'TSTA1'),
        (SELECT id_turma FROM tb_turma WHERE cd_turma = 'TSTTURMA' AND id_periodo_letivo =
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2)));
INSERT INTO tb_historico (id_matricula, qt_nota_a1, qt_nota_a2, qt_nota_p3, pc_frequencia, ds_situacao)
VALUES ((SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno) WHERE a.cd_matricula = 'TSTA1'),
        6, 7, 9, 90, 'aprovado');
SELECT qt_media_final FROM tb_historico;   -- esperado: 7.80

-- BARRADO: aluno do curso TST1 com o currículo do curso TST2 (FK composta)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    VALUES ('TSTA2', 'Aluno Errado', '00000000272', 'aluno.errado@iesb.br', '2004-01-01',
            (SELECT id_curso FROM tb_curso WHERE cd_curso = 'TST1'),
            (SELECT c.id_curriculo FROM tb_curriculo c JOIN tb_curso u USING (id_curso) WHERE u.cd_curso = 'TST2'));
    RAISE EXCEPTION 'FALHOU: aceitou currículo de outro curso';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'OK barrado (bloco 7): %', SQLERRM;
END $$;

-- BARRADO: CPF com 11 dígitos iguais
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA3', 'CPF Falso', '00000000000', 'cpf.falso@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou CPF 00000000000';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7b): %', SQLERRM;
END $$;

-- BARRADO: aluno nascido ontem (menos de 14 anos no ingresso)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA4', 'Bebe Prodigio', '12345678909', 'bebe@iesb.br', CURRENT_DATE - 1, u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou aluno com menos de 14 anos';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7c): %', SQLERRM;
END $$;

-- BARRADO: aprovado com média 0 (antes passava, porque só a frequência era conferida)
DO $$ BEGIN
    UPDATE tb_historico SET qt_nota_a1 = 0, qt_nota_a2 = 0, qt_nota_p3 = NULL
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou aprovado com média 0';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7d): %', SQLERRM;
END $$;

-- BARRADO: aprovado sem frequência lançada (CHECK com NULL passaria se não houvesse o IS NOT NULL)
DO $$ BEGIN
    UPDATE tb_historico SET pc_frequencia = NULL
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou aprovado sem frequência';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7e): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
-- Faz um rollback dos testes para não acumular lixo no banco
ROLLBACK;

-- esperado na aba Messages: 14 linhas "OK barrado (...)"