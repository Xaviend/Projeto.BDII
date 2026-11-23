/*
Autor: Iury Xavier Bomfim  - Modelagem Física e Desempenho
Objetivo: provar que as restrições do 01_modelo_fisico_v1.sql funcionam. Para cada regra:
          1 INSERT que PASSA (dado válido) e 1 que é BARRADO (dado inválido).

Como funciona:
  - tudo roda dentro de BEGIN ... ROLLBACK: no fim, nada fica gravado no banco;
  - cada teste negativo fica dentro de um bloco DO que CAPTURA o erro esperado e mostra
    "OK barrado: <mensagem do banco>" na aba Messages do pgAdmin;
  - se um teste negativo NÃO der erro, o bloco solta "FALHOU" e o script para: aí tem restrição faltando;
  - as conferências de valor (coluna gerada, horários) também são blocos DO: escrevem "OK conferido" ou param com "FALHOU".
  Então o script roda inteiro com F5, e é só ler a aba Messages. Roda antes ou depois da carga (03): só mexe nos dados TST.

Resultado esperado: 27 linhas "OK barrado (...)", 3 linhas "OK conferido (...)" e nenhuma "FALHOU".
Cobre: CHECK, UNIQUE (simples, composto e NULLS NOT DISTINCT), NOT NULL, FK simples e composta, EXCLUDE,
       DOMAIN, ENUM e coluna GERADA.

02_testes_restricoes_v1
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

-- BARRADO: frequência de 100,5% (domínio dm_percentual vai de 0 a 100)
DO $$ BEGIN
    PERFORM 100.5::dm_percentual;
    RAISE EXCEPTION 'FALHOU: dm_percentual aceitou 100.5';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 1b): %', SQLERRM;
END $$;

-- BARRADO: valor fora da lista do ENUM
DO $$ BEGIN
    PERFORM 'suspensa'::tp_status_matricula;
    RAISE EXCEPTION 'FALHOU: tp_status_matricula aceitou suspensa';
EXCEPTION WHEN invalid_text_representation THEN RAISE NOTICE 'OK barrado (bloco 1c): %', SQLERRM;
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

-- BARRADO: UF em minúscula (CHECK ck_cidade_sg_uf: 2 letras maiúsculas)
DO $$ BEGIN
    INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('Cidade UF Errada', 'df');
    RAISE EXCEPTION 'FALHOU: aceitou UF em minúscula';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 2c): %', SQLERRM;
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
-- CONFERE: a coluna gerada calculou 80 nas duas (a conferência aparece na aba Messages, não some no F5)
DO $$ BEGIN
    IF (SELECT count(*) FROM tb_disciplina WHERE cd_disciplina IN ('TSTBD1', 'TSTBD2') AND qt_ch_total = 80) <> 2 THEN
        RAISE EXCEPTION 'FALHOU: qt_ch_total não deu 80';
    END IF;
    RAISE NOTICE 'OK conferido (bloco 3): qt_ch_total = 80 nas duas disciplinas';
END $$;

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
-- CONFERE: os dois horários entraram (filtra a sala T101 do Campus Teste: vale também depois da carga)
DO $$ BEGIN
    IF (SELECT count(*) FROM tb_turma_horario h JOIN tb_sala s USING (id_sala) JOIN tb_campus c USING (id_campus)
         WHERE s.cd_sala = 'T101' AND c.nm_campus = 'Campus Teste') <> 2 THEN
        RAISE EXCEPTION 'FALHOU: esperava 2 horários na T101';
    END IF;
    RAISE NOTICE 'OK conferido (bloco 6): 2 horários na T101, um em cada semestre';
END $$;

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

-- BARRADO: turma com 0 vagas (CHECK ck_turma_vagas)
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('TSTVAGA0',
            (SELECT id_disciplina     FROM tb_disciplina     WHERE cd_disciplina = 'TSTBD1'),
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
            (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
            'noturno', 0);
    RAISE EXCEPTION 'FALHOU: aceitou turma com 0 vagas';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 6c): %', SQLERRM;
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
-- CONFERE: a média gerada deu 7,80 (filtra o aluno de teste: vale também depois da carga)
DO $$ BEGIN
    IF (SELECT h.qt_media_final FROM tb_historico h JOIN tb_matricula m USING (id_matricula)
          JOIN tb_aluno a USING (id_aluno) WHERE a.cd_matricula = 'TSTA1') IS DISTINCT FROM 7.80 THEN
        RAISE EXCEPTION 'FALHOU: média final diferente de 7,80';
    END IF;
    RAISE NOTICE 'OK conferido (bloco 7): qt_media_final = 7,80';
END $$;

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

-- BARRADO: matrícula sem turma. É o (1,1) do lado da FK virando NOT NULL.
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    VALUES ((SELECT id_aluno FROM tb_aluno WHERE cd_matricula = 'TSTA1'), NULL);
    RAISE EXCEPTION 'FALHOU: aceitou matrícula sem turma';
EXCEPTION WHEN not_null_violation THEN RAISE NOTICE 'OK barrado (bloco 7f): %', SQLERRM;
END $$;

-- BARRADO: matrícula numa turma que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    VALUES ((SELECT id_aluno FROM tb_aluno WHERE cd_matricula = 'TSTA1'), -1);
    RAISE EXCEPTION 'FALHOU: aceitou turma inexistente';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'OK barrado (bloco 7g): %', SQLERRM;
END $$;

-- BARRADO: o mesmo aluno duas vezes na mesma turma (UNIQUE uq_matricula_aluno_turma)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    SELECT id_aluno, id_turma FROM tb_matricula JOIN tb_aluno USING (id_aluno) WHERE cd_matricula = 'TSTA1';
    RAISE EXCEPTION 'FALHOU: aceitou matrícula repetida';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK barrado (bloco 7h): %', SQLERRM;
END $$;

-- BARRADO: segundo histórico para a mesma matrícula. É o "máx 1" do (0,1) virando UNIQUE.
DO $$ BEGIN
    INSERT INTO tb_historico (id_matricula)
    SELECT id_matricula FROM tb_matricula JOIN tb_aluno USING (id_aluno) WHERE cd_matricula = 'TSTA1';
    RAISE EXCEPTION 'FALHOU: aceitou dois históricos na mesma matrícula';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK barrado (bloco 7i): %', SQLERRM;
END $$;

-- BARRADO: reprovado por nota com média 7,80 (CHECK ck_historico_rep_nota)
DO $$ BEGIN
    UPDATE tb_historico SET ds_situacao = 'reprovado_nota'
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou reprovado por nota com média 7,80';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7j): %', SQLERRM;
END $$;

-- BARRADO: reprovado por falta com 90% de frequência (CHECK ck_historico_falta)
DO $$ BEGIN
    UPDATE tb_historico SET ds_situacao = 'reprovado_falta'
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou reprovado por falta com 90%%';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7k): %', SQLERRM;
END $$;

-- BARRADO: gravar a média à mão (coluna GERADA: só o banco calcula)
DO $$ BEGIN
    UPDATE tb_historico SET qt_media_final = 10
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou média digitada';
EXCEPTION WHEN generated_always THEN RAISE NOTICE 'OK barrado (bloco 7l): %', SQLERRM;
END $$;

-- BARRADO: outro aluno com o mesmo CPF (UNIQUE uq_aluno_cpf)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA5', 'CPF Repetido', '00000000191', 'cpf.repetido@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou CPF repetido';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK barrado (bloco 7m): %', SQLERRM;
END $$;

-- BARRADO: e-mail sem @ (CHECK ck_aluno_email)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA6', 'Email Errado', '12345678909', 'sem-arroba.iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou e-mail sem @';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK barrado (bloco 7n): %', SQLERRM;
END $$;


------------------------------------------------------------------------------------------------------------------------------
-- Faz um rollback dos testes para não acumular lixo no banco
ROLLBACK;

-- esperado na aba Messages: 27 linhas "OK barrado (...)" e 3 linhas "OK conferido (...)"