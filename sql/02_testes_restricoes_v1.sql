/*
Autor: Iury Xavier Bomfim  - Modelagem Física e Desempenho
Revisão (23/11, Arthur): um teste para CADA restrição do 01, conferência do nome da restrição que barrou e bloco 8
          (cobertura conferida contra o catálogo do banco).
Objetivo: provar que as restrições do 01_modelo_fisico_v1.sql funcionam. Para cada regra:
          1 INSERT que PASSA (dado válido) e 1 que é BARRADO (dado inválido).

Como funciona:
  - tudo roda dentro de BEGIN ... ROLLBACK: no fim, nada fica gravado no banco;
  - cada teste negativo fica dentro de um bloco DO que CAPTURA o erro esperado e confere, pela mensagem do banco,
    se quem barrou foi a restrição ESPERADA (fn_barrado). Se foi, mostra "OK barrado (...): <mensagem do banco>"
    na aba Messages do pgAdmin;
  - se um teste negativo NÃO der erro, ou se outra restrição barrar no lugar da esperada, o script para com
    "FALHOU": aí tem restrição faltando ou errada;
  - as conferências de valor (coluna gerada, horários) também são blocos DO: escrevem "OK conferido" ou param com "FALHOU";
  - o bloco 8 lê no catálogo (pg_constraint) todas as restrições do schema e para com "FALHOU" se alguma
    não foi barrada por nenhum teste daqui. Restrição nova no 01 sem teste novo aqui = FALHOU.
  Então o script roda inteiro com F5, e é só ler a aba Messages. Roda antes ou depois da carga (03): só mexe nos dados TST.

Resultado esperado: 75 linhas "OK barrado (...)", 4 linhas "OK conferido (...)" e nenhuma "FALHOU".
Cobre: CHECK, UNIQUE (simples, composto e NULLS NOT DISTINCT), NOT NULL, PK, FK simples e composta, EXCLUDE,
       DOMAIN, ENUM e coluna GERADA.

02_testes_restricoes_v1
*/
------------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

BEGIN;

------------------------------------------------------------------------------------------------------------------------------
--BLOCO 0 - FERRAMENTA DOS TESTES (some no ROLLBACK do fim, junto com os dados TST)
-- tst_testadas: o nome de cada restrição que barrou dado errado (o bloco 8 confere contra o catálogo).
-- fn_barrado: o banco escreve o nome da restrição entre aspas na mensagem de erro (ex.: violates check constraint
-- "ck_cidade_sg_uf"). A função confere se o nome esperado está lá. Sem isso, um teste podia dar "OK barrado" por causa
-- de OUTRA restrição (ex.: um CPF repetido barrado pelo formato, e não pelo UNIQUE).
CREATE TEMP TABLE tst_testadas (nm_restricao text PRIMARY KEY);

CREATE FUNCTION pg_temp.fn_barrado(p_teste text, p_restricao text, p_erro text) RETURNS void
LANGUAGE plpgsql AS $f$
BEGIN
    IF position('"' || p_restricao || '"' IN p_erro) = 0 THEN
        RAISE EXCEPTION 'FALHOU (%): esperava a restricao %, mas o banco barrou por outro motivo: %',
                        p_teste, p_restricao, p_erro;
    END IF;
    INSERT INTO tst_testadas VALUES (p_restricao) ON CONFLICT DO NOTHING;
    RAISE NOTICE 'OK barrado (%): %', p_teste, p_erro;
END $f$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 1 - DOMÍNIOS E TIPOS

-- PASSA: 7,5 é uma nota válida no domínio dm_nota
SELECT 7.5::dm_nota AS nota_valida;

-- BARRADO: 10,5 passa do limite do domínio (0 a 10)
DO $$ BEGIN
    PERFORM 10.5::dm_nota;
    RAISE EXCEPTION 'FALHOU: dm_nota aceitou 10.5';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 1', 'dm_nota_check', SQLERRM);
END $$;

-- BARRADO: frequência de 100,5% (domínio dm_percentual vai de 0 a 100)
DO $$ BEGIN
    PERFORM 100.5::dm_percentual;
    RAISE EXCEPTION 'FALHOU: dm_percentual aceitou 100.5';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 1b', 'dm_percentual_check', SQLERRM);
END $$;

-- BARRADO: valor fora da lista do ENUM (enum não é restrição com nome: confere só o tipo do erro)
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
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 2', 'uq_feriado_dt_campus', SQLERRM);
END $$;

-- BARRADO: cidade com nome só de espaços (NOT NULL sozinho deixaria passar)
DO $$ BEGIN
    INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('   ', 'DF');
    RAISE EXCEPTION 'FALHOU: aceitou cidade sem nome';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 2b', 'ck_cidade_nm', SQLERRM);
END $$;

-- BARRADO: UF em minúscula (CHECK ck_cidade_sg_uf: 2 letras maiúsculas)
DO $$ BEGIN
    INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('Cidade UF Errada', 'df');
    RAISE EXCEPTION 'FALHOU: aceitou UF em minúscula';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 2c', 'ck_cidade_sg_uf', SQLERRM);
END $$;

-- BARRADO: id de cidade repetido (PK). O id é gerado pelo banco; aqui ele é digitado de propósito.
-- As 17 PKs são iguais (id gerado pelo banco): esta vale como exemplo de todas.
DO $$ BEGIN
    INSERT INTO tb_cidade (id_cidade, nm_cidade, sg_uf)
    SELECT id_cidade, 'Cidade Id Repetido', 'GO' FROM tb_cidade WHERE nm_cidade = 'Cidade Teste';
    RAISE EXCEPTION 'FALHOU: aceitou id de cidade repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 2d', 'pk_cidade', SQLERRM);
END $$;

-- BARRADO: a mesma cidade na mesma UF de novo (UNIQUE composto)
DO $$ BEGIN
    INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('Cidade Teste', 'DF');
    RAISE EXCEPTION 'FALHOU: aceitou cidade repetida na mesma UF';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 2e', 'uq_cidade_nm_uf', SQLERRM);
END $$;

-- BARRADO: campus com nome só de espaços
DO $$ BEGIN
    INSERT INTO tb_campus (nm_campus, id_cidade)
    SELECT '   ', id_cidade FROM tb_cidade WHERE nm_cidade = 'Cidade Teste';
    RAISE EXCEPTION 'FALHOU: aceitou campus sem nome';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 2f', 'ck_campus_nm', SQLERRM);
END $$;

-- BARRADO: dois campus com o mesmo nome
DO $$ BEGIN
    INSERT INTO tb_campus (nm_campus, id_cidade)
    SELECT 'Campus Teste', id_cidade FROM tb_cidade WHERE nm_cidade = 'Cidade Teste';
    RAISE EXCEPTION 'FALHOU: aceitou campus repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 2g', 'uq_campus_nm', SQLERRM);
END $$;

-- BARRADO: campus numa cidade que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_campus (nm_campus, id_cidade) VALUES ('Campus Sem Cidade', -1);
    RAISE EXCEPTION 'FALHOU: aceitou campus em cidade inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 2h', 'fk_campus_cidade', SQLERRM);
END $$;

-- BARRADO: feriado local de um campus que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_feriado (dt_feriado, ds_feriado, id_campus) VALUES ('2099-11-16', 'Feriado sem campus', -1);
    RAISE EXCEPTION 'FALHOU: aceitou feriado de campus inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 2i', 'fk_feriado_campus', SQLERRM);
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
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 3', 'ck_disciplina_ch', SQLERRM);
END $$;

-- BARRADO: disciplina com nome só de espaços
DO $$ BEGIN
    INSERT INTO tb_disciplina (cd_disciplina, nm_disciplina, qt_ch_teorica, qt_ch_pratica)
    VALUES ('TSTBD9', '   ', 40, 0);
    RAISE EXCEPTION 'FALHOU: aceitou disciplina sem nome';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 3b', 'ck_disciplina_texto', SQLERRM);
END $$;

-- BARRADO: duas disciplinas com o mesmo código
DO $$ BEGIN
    INSERT INTO tb_disciplina (cd_disciplina, nm_disciplina, qt_ch_teorica, qt_ch_pratica)
    VALUES ('TSTBD1', 'BD Teste Repetida', 40, 0);
    RAISE EXCEPTION 'FALHOU: aceitou código de disciplina repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 3c', 'uq_disciplina_cd', SQLERRM);
END $$;

-- BARRADO: curso com carga horária total 0
DO $$ BEGIN
    INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
    SELECT 'TST3', 'Curso Sem Carga', 'bacharelado', 0, id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou curso com carga 0';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 3d', 'ck_curso_ch', SQLERRM);
END $$;

-- BARRADO: curso com código só de espaços
DO $$ BEGIN
    INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
    SELECT '   ', 'Curso Sem Codigo', 'bacharelado', 3200, id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou curso sem código';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 3e', 'ck_curso_texto', SQLERRM);
END $$;

-- BARRADO: dois cursos com o mesmo código
DO $$ BEGIN
    INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
    SELECT 'TST1', 'Curso Repetido', 'bacharelado', 3200, id_campus FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou código de curso repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 3f', 'uq_curso_cd', SQLERRM);
END $$;

-- BARRADO: curso num campus que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
    VALUES ('TST4', 'Curso Sem Campus', 'bacharelado', 3200, -1);
    RAISE EXCEPTION 'FALHOU: aceitou curso em campus inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 3g', 'fk_curso_campus', SQLERRM);
END $$;

-- BARRADO: currículo com vigência em 1980 (CHECK de 1990 a 2100)
DO $$ BEGIN
    INSERT INTO tb_curriculo (id_curso, aa_vigencia) SELECT id_curso, 1980 FROM tb_curso WHERE cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou currículo de 1980';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 3h', 'ck_curriculo_aa', SQLERRM);
END $$;

-- BARRADO: dois currículos do mesmo curso com a mesma vigência
DO $$ BEGIN
    INSERT INTO tb_curriculo (id_curso, aa_vigencia) SELECT id_curso, 2026 FROM tb_curso WHERE cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou currículo repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 3i', 'uq_curriculo_curso_aa', SQLERRM);
END $$;

-- BARRADO: currículo de um curso que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_curriculo (id_curso, aa_vigencia) VALUES (-1, 2026);
    RAISE EXCEPTION 'FALHOU: aceitou currículo de curso inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 3j', 'fk_curriculo_curso', SQLERRM);
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
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 4', 'ck_pre_req_si_mesma', SQLERRM);
END $$;

-- BARRADO: o mesmo pré-requisito duas vezes
DO $$ BEGIN
    INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
    VALUES ((SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD2'),
            (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'));
    RAISE EXCEPTION 'FALHOU: aceitou pré-requisito repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 4b', 'uq_pre_req_par', SQLERRM);
END $$;

-- BARRADO: pré-requisito para uma disciplina que não existe (FK do lado de quem exige)
DO $$ BEGIN
    INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
    VALUES (-1, (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'));
    RAISE EXCEPTION 'FALHOU: aceitou pré-requisito de disciplina inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 4c', 'fk_pre_req_disc', SQLERRM);
END $$;

-- BARRADO: exigir uma disciplina que não existe (FK do lado do requisito)
DO $$ BEGIN
    INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
    VALUES ((SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'), -1);
    RAISE EXCEPTION 'FALHOU: aceitou requisito inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 4d', 'fk_pre_req_requisito', SQLERRM);
END $$;

-- BARRADO: disciplina no 13º semestre da grade (CHECK de 1 a 12)
DO $$ BEGIN
    INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade)
    VALUES ((SELECT c.id_curriculo FROM tb_curriculo c JOIN tb_curso u USING (id_curso) WHERE u.cd_curso = 'TST1'),
            (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD2'), 13);
    RAISE EXCEPTION 'FALHOU: aceitou semestre 13 na grade';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 4e', 'ck_cd_periodo_grade', SQLERRM);
END $$;

-- BARRADO: a mesma disciplina duas vezes no mesmo currículo
DO $$ BEGIN
    INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade)
    VALUES ((SELECT c.id_curriculo FROM tb_curriculo c JOIN tb_curso u USING (id_curso) WHERE u.cd_curso = 'TST1'),
            (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'), 4);
    RAISE EXCEPTION 'FALHOU: aceitou disciplina repetida na grade';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 4f', 'uq_cd_curriculo_disc', SQLERRM);
END $$;

-- BARRADO: grade de um currículo que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade)
    VALUES (-1, (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD2'), 1);
    RAISE EXCEPTION 'FALHOU: aceitou grade de currículo inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 4g', 'fk_cd_curriculo', SQLERRM);
END $$;

-- BARRADO: disciplina que não existe na grade (FK)
DO $$ BEGIN
    INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade)
    VALUES ((SELECT c.id_curriculo FROM tb_curriculo c JOIN tb_curso u USING (id_curso) WHERE u.cd_curso = 'TST2'), -1, 1);
    RAISE EXCEPTION 'FALHOU: aceitou disciplina inexistente na grade';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 4h', 'fk_cd_disciplina', SQLERRM);
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
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5', 'ck_periodo_semestre', SQLERRM);
END $$;

-- BARRADO: período "2098/1" com datas de 1980 (ano das datas não bate com aa_periodo)
DO $$ BEGIN
    INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
    VALUES (2098, 1, '1980-01-01', '1980-01-02');
    RAISE EXCEPTION 'FALHOU: aceitou período com ano errado';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5b', 'ck_periodo_ano', SQLERRM);
END $$;

-- BARRADO: período que termina antes de começar
DO $$ BEGIN
    INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
    VALUES (2098, 1, '2098-06-30', '2098-02-01');
    RAISE EXCEPTION 'FALHOU: aceitou período com fim antes do início';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5c', 'ck_periodo_datas', SQLERRM);
END $$;

-- BARRADO: o semestre 2099/1 cadastrado duas vezes
DO $$ BEGIN
    INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim)
    VALUES (2099, 1, '2099-02-02', '2099-06-29');
    RAISE EXCEPTION 'FALHOU: aceitou o mesmo semestre duas vezes';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 5d', 'uq_periodo_aa_sem', SQLERRM);
END $$;

-- BARRADO: professor com e-mail sem @
DO $$ BEGIN
    INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
    VALUES ('TSTP2', 'Professor Email Errado', 'sem-arroba.iesb.br', 'mestre');
    RAISE EXCEPTION 'FALHOU: aceitou e-mail de professor sem @';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5e', 'ck_professor_email', SQLERRM);
END $$;

-- BARRADO: professor com nome só de espaços
DO $$ BEGIN
    INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
    VALUES ('TSTP3', '   ', 'prof.sem.nome@iesb.br', 'mestre');
    RAISE EXCEPTION 'FALHOU: aceitou professor sem nome';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5f', 'ck_professor_texto', SQLERRM);
END $$;

-- BARRADO: dois professores com o mesmo e-mail
DO $$ BEGIN
    INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
    VALUES ('TSTP4', 'Professor Email Repetido', 'prof.teste@iesb.br', 'doutor');
    RAISE EXCEPTION 'FALHOU: aceitou e-mail de professor repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 5g', 'uq_professor_email', SQLERRM);
END $$;

-- BARRADO: dois professores com a mesma matrícula
DO $$ BEGIN
    INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
    VALUES ('TSTP1', 'Professor Matricula Repetida', 'prof.outro@iesb.br', 'doutor');
    RAISE EXCEPTION 'FALHOU: aceitou matrícula de professor repetida';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 5h', 'uq_professor_matricula', SQLERRM);
END $$;

-- BARRADO: sala com capacidade 0
DO $$ BEGIN
    INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo)
    SELECT id_campus, 'T102', 0, 'teorica' FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou sala com capacidade 0';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5i', 'ck_sala_capacidade', SQLERRM);
END $$;

-- BARRADO: sala com código só de espaços
DO $$ BEGIN
    INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo)
    SELECT id_campus, '   ', 40, 'teorica' FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou sala sem código';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 5j', 'ck_sala_cd', SQLERRM);
END $$;

-- BARRADO: duas salas T101 no mesmo campus
DO $$ BEGIN
    INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo)
    SELECT id_campus, 'T101', 30, 'teorica' FROM tb_campus WHERE nm_campus = 'Campus Teste';
    RAISE EXCEPTION 'FALHOU: aceitou sala repetida no campus';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 5k', 'uq_sala_campus_cd', SQLERRM);
END $$;

-- BARRADO: sala num campus que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo) VALUES (-1, 'T103', 40, 'teorica');
    RAISE EXCEPTION 'FALHOU: aceitou sala em campus inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 5l', 'fk_sala_campus', SQLERRM);
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
EXCEPTION WHEN exclusion_violation THEN PERFORM pg_temp.fn_barrado('bloco 6', 'ex_th_choque_sala', SQLERRM);
END $$;

-- BARRADO: horário dizendo que a turma de 2099/2 é de 2099/1 (FK composta não deixa divergir)
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, p1.id_periodo_letivo, s.id_sala, 3, '08:00', '09:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_periodo_letivo p1, tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2
       AND p1.aa_periodo = 2099 AND p1.cd_semestre = 1 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou horário com semestre diferente do da turma';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6b', 'fk_th_turma', SQLERRM);
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
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 6c', 'ck_turma_vagas', SQLERRM);
END $$;

-- BARRADO: turma com código só de espaços
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('   ',
            (SELECT id_disciplina     FROM tb_disciplina     WHERE cd_disciplina = 'TSTBD1'),
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
            (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
            'noturno', 40);
    RAISE EXCEPTION 'FALHOU: aceitou turma sem código';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 6d', 'ck_turma_cd', SQLERRM);
END $$;

-- BARRADO: a mesma turma (código, disciplina e semestre) duas vezes
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('TSTTURMA',
            (SELECT id_disciplina     FROM tb_disciplina     WHERE cd_disciplina = 'TSTBD2'),
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
            (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
            'matutino', 30);
    RAISE EXCEPTION 'FALHOU: aceitou turma repetida';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 6e', 'uq_turma_cd', SQLERRM);
END $$;

-- BARRADO: turma de uma disciplina que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('TSTFK1', -1,
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
            (SELECT id_professor      FROM tb_professor      WHERE cd_matricula = 'TSTP1'),
            'noturno', 40);
    RAISE EXCEPTION 'FALHOU: aceitou turma de disciplina inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6f', 'fk_turma_disciplina', SQLERRM);
END $$;

-- BARRADO: turma num semestre que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('TSTFK2', (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'), -1,
            (SELECT id_professor FROM tb_professor WHERE cd_matricula = 'TSTP1'),
            'noturno', 40);
    RAISE EXCEPTION 'FALHOU: aceitou turma em semestre inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6g', 'fk_turma_periodo', SQLERRM);
END $$;

-- BARRADO: turma com um professor que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
    VALUES ('TSTFK3', (SELECT id_disciplina FROM tb_disciplina WHERE cd_disciplina = 'TSTBD1'),
            (SELECT id_periodo_letivo FROM tb_periodo_letivo WHERE aa_periodo = 2099 AND cd_semestre = 2),
            -1, 'noturno', 40);
    RAISE EXCEPTION 'FALHOU: aceitou turma com professor inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6h', 'fk_turma_professor', SQLERRM);
END $$;

-- BARRADO: horário no dia 8 da semana (CHECK de 1 a 7)
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, t.id_periodo_letivo, s.id_sala, 8, '08:00', '09:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou dia 8 da semana';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 6i', 'ck_th_dd_semana', SQLERRM);
END $$;

-- BARRADO: aula que termina na mesma hora em que começa (duração zero).
-- Só o CHECK barra este caso: o intervalo 10:00-10:00 é vazio e não choca com nada no EXCLUDE.
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, t.id_periodo_letivo, s.id_sala, 2, '10:00', '10:00'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou aula com duração zero';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 6j', 'ck_th_horario', SQLERRM);
END $$;

-- BARRADO: horário numa sala que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, t.id_periodo_letivo, -1, 2, '08:00', '09:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo)
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2;
    RAISE EXCEPTION 'FALHOU: aceitou horário em sala inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6k', 'fk_th_sala', SQLERRM);
END $$;

-- BARRADO: horário num semestre que não existe (FK simples para tb_periodo_letivo)
-- Semestre inexistente quebra também a FK composta fk_th_turma, e o PostgreSQL pode avisar qualquer uma das duas
-- (a ordem muda de um banco para outro). Para provar a fk_th_periodo sozinha, o bloco tira a composta só aqui dentro:
-- o erro esperado desfaz o DROP junto com o INSERT, e a fk_th_turma volta a valer na linha seguinte.
DO $$ BEGIN
    ALTER TABLE tb_turma_horario DROP CONSTRAINT fk_th_turma;
    INSERT INTO tb_turma_horario (id_turma, id_periodo_letivo, id_sala, dd_semana, hr_inicio, hr_fim)
    SELECT t.id_turma, -1, s.id_sala, 2, '08:00', '09:40'
      FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo), tb_sala s
     WHERE t.cd_turma = 'TSTTURMA' AND p.cd_semestre = 2 AND s.cd_sala = 'T101';
    RAISE EXCEPTION 'FALHOU: aceitou horário em semestre inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 6l', 'fk_th_periodo', SQLERRM);
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
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 7', 'fk_aluno_curriculo', SQLERRM);
END $$;

-- BARRADO: CPF com 11 dígitos iguais
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA3', 'CPF Falso', '00000000000', 'cpf.falso@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou CPF 00000000000';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7b', 'ck_aluno_cpf', SQLERRM);
END $$;

-- BARRADO: aluno nascido ontem (menos de 14 anos no ingresso)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA4', 'Bebe Prodigio', '12345678909', 'bebe@iesb.br', CURRENT_DATE - 1, u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou aluno com menos de 14 anos';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7c', 'ck_aluno_datas', SQLERRM);
END $$;

-- BARRADO: aprovado com média 0 (antes passava, porque só a frequência era conferida)
DO $$ BEGIN
    UPDATE tb_historico SET qt_nota_a1 = 0, qt_nota_a2 = 0, qt_nota_p3 = NULL
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou aprovado com média 0';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7d', 'ck_historico_aprovado', SQLERRM);
END $$;

-- BARRADO: aprovado sem frequência lançada (CHECK com NULL passaria se não houvesse o IS NOT NULL)
DO $$ BEGIN
    UPDATE tb_historico SET pc_frequencia = NULL
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou aprovado sem frequência';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7e', 'ck_historico_aprovado', SQLERRM);
END $$;

-- BARRADO: matrícula sem turma. É o (1,1) do lado da FK virando NOT NULL.
-- (NOT NULL não tem nome de restrição no PostgreSQL 16 e 17: a mensagem cita a coluna)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    VALUES ((SELECT id_aluno FROM tb_aluno WHERE cd_matricula = 'TSTA1'), NULL);
    RAISE EXCEPTION 'FALHOU: aceitou matrícula sem turma';
EXCEPTION WHEN not_null_violation THEN PERFORM pg_temp.fn_barrado('bloco 7f', 'id_turma', SQLERRM);
END $$;

-- BARRADO: matrícula numa turma que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    VALUES ((SELECT id_aluno FROM tb_aluno WHERE cd_matricula = 'TSTA1'), -1);
    RAISE EXCEPTION 'FALHOU: aceitou turma inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 7g', 'fk_matricula_turma', SQLERRM);
END $$;

-- BARRADO: o mesmo aluno duas vezes na mesma turma (UNIQUE uq_matricula_aluno_turma)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    SELECT id_aluno, id_turma FROM tb_matricula JOIN tb_aluno USING (id_aluno) WHERE cd_matricula = 'TSTA1';
    RAISE EXCEPTION 'FALHOU: aceitou matrícula repetida';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 7h', 'uq_matricula_aluno_turma', SQLERRM);
END $$;

-- BARRADO: segundo histórico para a mesma matrícula. É o "máx 1" do (0,1) virando UNIQUE.
DO $$ BEGIN
    INSERT INTO tb_historico (id_matricula)
    SELECT id_matricula FROM tb_matricula JOIN tb_aluno USING (id_aluno) WHERE cd_matricula = 'TSTA1';
    RAISE EXCEPTION 'FALHOU: aceitou dois históricos na mesma matrícula';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 7i', 'uq_historico_matricula', SQLERRM);
END $$;

-- BARRADO: reprovado por nota com média 7,80 (CHECK ck_historico_rep_nota)
DO $$ BEGIN
    UPDATE tb_historico SET ds_situacao = 'reprovado_nota'
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou reprovado por nota com média 7,80';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7j', 'ck_historico_rep_nota', SQLERRM);
END $$;

-- BARRADO: reprovado por falta com 90% de frequência (CHECK ck_historico_falta)
DO $$ BEGIN
    UPDATE tb_historico SET ds_situacao = 'reprovado_falta'
     WHERE id_matricula = (SELECT m.id_matricula FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
                            WHERE a.cd_matricula = 'TSTA1');
    RAISE EXCEPTION 'FALHOU: aceitou reprovado por falta com 90%%';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7k', 'ck_historico_falta', SQLERRM);
END $$;

-- BARRADO: gravar a média à mão (coluna GERADA: só o banco calcula; não é restrição com nome)
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
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 7m', 'uq_aluno_cpf', SQLERRM);
END $$;

-- BARRADO: e-mail sem @ (CHECK ck_aluno_email)
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA6', 'Email Errado', '12345678909', 'sem-arroba.iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou e-mail sem @';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7n', 'ck_aluno_email', SQLERRM);
END $$;

-- BARRADO: aluno com nome só de espaços
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA7', '   ', '12345678909', 'sem.nome@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou aluno sem nome';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7o', 'ck_aluno_texto', SQLERRM);
END $$;

-- BARRADO: outro aluno com o mesmo e-mail
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA8', 'Email Repetido', '12345678909', 'aluno.teste@iesb.br', '2004-01-01', u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou e-mail de aluno repetido';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 7p', 'uq_aluno_email', SQLERRM);
END $$;

-- BARRADO: outro aluno com a mesma matrícula
DO $$ BEGIN
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA1', 'Matricula Repetida', '12345678909', 'matricula.repetida@iesb.br', '2004-01-01',
           u.id_curso, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou matrícula de aluno repetida';
EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.fn_barrado('bloco 7q', 'uq_aluno_matricula', SQLERRM);
END $$;

-- BARRADO: aluno num curso que não existe (FK simples)
-- Curso inexistente quebra também a FK composta fk_aluno_curriculo, e o PostgreSQL pode avisar qualquer uma das duas.
-- Como no bloco 6l, a composta sai só aqui dentro e o erro esperado desfaz o DROP.
DO $$ BEGIN
    ALTER TABLE tb_aluno DROP CONSTRAINT fk_aluno_curriculo;
    INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo)
    SELECT 'TSTA9', 'Curso Inexistente', '12345678909', 'curso.inexistente@iesb.br', '2004-01-01', -1, c.id_curriculo
      FROM tb_curso u JOIN tb_curriculo c USING (id_curso) WHERE u.cd_curso = 'TST1';
    RAISE EXCEPTION 'FALHOU: aceitou aluno em curso inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 7r', 'fk_aluno_curso', SQLERRM);
END $$;

-- BARRADO: matrícula de um aluno que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_matricula (id_aluno, id_turma)
    SELECT -1, id_turma FROM tb_matricula JOIN tb_aluno USING (id_aluno) WHERE cd_matricula = 'TSTA1';
    RAISE EXCEPTION 'FALHOU: aceitou matrícula de aluno inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 7s', 'fk_matricula_aluno', SQLERRM);
END $$;

-- BARRADO: histórico de uma matrícula que não existe (FK)
DO $$ BEGIN
    INSERT INTO tb_historico (id_matricula) VALUES (-1);
    RAISE EXCEPTION 'FALHOU: aceitou histórico de matrícula inexistente';
EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.fn_barrado('bloco 7t', 'fk_historico_matricula', SQLERRM);
END $$;

-- BARRADO: linha de log com ação que não existe (CHECK: só INSERT, UPDATE ou DELETE).
-- O log não tem FK de propósito (continua existindo se a matrícula for apagada), então o id -1 não é barrado.
DO $$ BEGIN
    INSERT INTO tb_log_matricula (id_matricula, ds_acao) VALUES (-1, 'TRUNCATE');
    RAISE EXCEPTION 'FALHOU: aceitou ação de log inválida';
EXCEPTION WHEN check_violation THEN PERFORM pg_temp.fn_barrado('bloco 7u', 'ck_log_acao', SQLERRM);
END $$;


------------------------------------------------------------------------------------------------------------------------------
--BLOCO 8 - COBERTURA: toda restrição do schema foi barrada por algum teste acima
-- Lê no catálogo (pg_constraint) as restrições CHECK, UNIQUE, FK e EXCLUDE do schema projeto_bd2 (inclusive as dos
-- domínios) e compara com tst_testadas. Restrição sem teste = FALHOU com o nome dela.
-- Ficam fora, com o motivo:
--   uq_curriculo_id_curso e uq_turma_id_periodo: contêm a PK, então nunca repetem. Existem só para as FKs compostas
--     fk_aluno_curriculo e fk_th_turma apontarem para elas, e essas duas FKs têm teste (blocos 7 e 6b);
--   as PKs: o id é gerado pelo banco; a PK da tb_cidade tem teste como exemplo (bloco 2d).
DO $$
DECLARE
    v_sem_teste text;
    v_testadas  int;
BEGIN
    SELECT string_agg(c.conname, ', ' ORDER BY c.conname) INTO v_sem_teste
      FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE n.nspname = 'projeto_bd2' AND c.contype IN ('c', 'u', 'f', 'x')
       AND c.conname NOT IN ('uq_curriculo_id_curso', 'uq_turma_id_periodo')
       AND NOT EXISTS (SELECT 1 FROM tst_testadas t WHERE t.nm_restricao = c.conname);
    IF v_sem_teste IS NOT NULL THEN
        RAISE EXCEPTION 'FALHOU (bloco 8): restricao do schema sem teste neste script: %', v_sem_teste;
    END IF;
    SELECT count(*) INTO v_testadas
      FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE n.nspname = 'projeto_bd2' AND c.contype IN ('c', 'u', 'f', 'x')
       AND EXISTS (SELECT 1 FROM tst_testadas t WHERE t.nm_restricao = c.conname);
    RAISE NOTICE 'OK conferido (bloco 8): as % restricoes CHECK, UNIQUE, FK e EXCLUDE do schema tem teste (fora as 2 que so servem de alvo para FK composta)',
                 v_testadas;
END $$;


------------------------------------------------------------------------------------------------------------------------------
-- Faz um rollback dos testes para não acumular lixo no banco
ROLLBACK;

-- esperado na aba Messages: 75 linhas "OK barrado (...)", 4 linhas "OK conferido (...)" e nenhuma "FALHOU"
