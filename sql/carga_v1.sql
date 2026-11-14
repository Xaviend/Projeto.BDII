/*
Autor: Iury Xavier Bomfim  - Modelagem Física e Desempenho
Objetivo: popular o schema projeto_bd2 (criado pelo modelo_fisico_v1.sql) com dados de teste, usando generate_series.
          O Marco 1 pede no mínimo 100 alunos, 6 turmas e 300 matrículas. Aqui ficam bem acima disso (2000 alunos,
          1536 turmas, ~30 mil matrículas) de propósito: com poucas linhas o PostgreSQL prefere ler a tabela inteira
          e o EXPLAIN de antes e depois dos índices (indices_v1.sql) não mostraria ganho nenhum.

Os dados são SINTÉTICOS (nomes, CPFs, e-mails e notas inventados). Não vêm do schema academico do professor.

Como rodar:
  - rodar DEPOIS do modelo_fisico_v1.sql (precisa das 17 tabelas vazias ou não: o script limpa tudo antes);
  - tudo roda dentro de BEGIN ... COMMIT: se qualquer INSERT quebrar uma restrição, nada fica gravado;
  - pode rodar quantas vezes quiser: o TRUNCATE do início zera as tabelas e os ids (RESTART IDENTITY);
  - os dados são determinísticos (sem random()): toda execução gera exatamente os mesmos dados.

Regras que a carga respeita (para os dados serem coerentes e não só aceitos pelo banco):
  - 8 períodos letivos (2023/1 até 2026/2); 2026/2 é o semestre atual;
  - cada aluno cursa as disciplinas do semestre da grade em que está, um semestre da grade por período letivo;
  - só se reprova em disciplina que NINGUÉM exige como pré-requisito (assim ninguém cursa uma disciplina
    sem ter sido aprovado no pré-requisito dela);
  - nos semestres passados a matrícula é 'concluida' e tem histórico com nota; em 2026/2 é 'ativa' e o histórico
    está 'cursando' (só A1 lançada); 'trancada' e 'cancelada' ficam SEM histórico: é o (0,1) do modelo;
  - cada aluno cai sempre na mesma seção (A a H) em todas as disciplinas, e as seções têm horários que nunca
    se chocam entre si: nenhum aluno tem duas aulas no mesmo horário;
  - a turma de Banco de Dados II (CCO072) de 2026/2, seção A, fica com EXATAMENTE 1 vaga livre: é a "última vaga"
    para a frente de transações e concorrência reproduzir a anomalia.

carga_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;

BEGIN;

------------------------------------------------------------------------------------------------------------------------
-- BLOCO 0 - LIMPEZA E AUXILIARES

-- Apaga os dados (não a estrutura) e reinicia os ids: o script pode rodar várias vezes.
TRUNCATE tb_log_matricula, tb_historico, tb_matricula, tb_turma_horario, tb_turma, tb_aluno,
         tb_pre_requisito, tb_curriculo_disciplina, tb_disciplina, tb_curriculo, tb_curso,
         tb_sala, tb_periodo_letivo, tb_professor, tb_feriado, tb_campus, tb_cidade
         RESTART IDENTITY CASCADE;

-- "Sorteio" SEM random(): transforma um texto em um número de 0 a p_n - 1.
-- O mesmo texto dá sempre o mesmo número, então a carga é reproduzível. Função TEMPORÁRIA (pg_temp): some
-- sozinha quando a sessão fecha, não fica no schema.
CREATE OR REPLACE FUNCTION pg_temp.fn_sorteio(p_semente TEXT, p_n INT) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$
    -- md5 vira texto hexadecimal; pegamos 7 dígitos hex (28 bits) e convertemos para inteiro
    SELECT (('x' || substr(md5(p_semente), 1, 7))::bit(28)::int) % p_n
$$;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 1 - CIDADE, CAMPUS E FERIADO

INSERT INTO tb_cidade (nm_cidade, sg_uf) VALUES ('Brasília', 'DF'), ('Goiânia', 'GO');

-- O campus de Goiânia é fictício e fica SEM cursos de propósito: serve para a consulta com LEFT JOIN (junção
-- externa com agregação) mostrar um campus com contagem 0.
INSERT INTO tb_campus (nm_campus, id_cidade)
SELECT v.nm_campus, c.id_cidade
  FROM (VALUES ('Asa Sul', 'Brasília'), ('Goiânia Centro', 'Goiânia')) AS v (nm_campus, nm_cidade)
  JOIN tb_cidade c ON c.nm_cidade = v.nm_cidade;

-- id_campus NULL = feriado nacional (o (0,1) do modelo); preenchido = feriado só daquele campus
INSERT INTO tb_feriado (dt_feriado, ds_feriado, id_campus)
SELECT v.dt_feriado::date, v.ds_feriado, c.id_campus
  FROM (VALUES ('2026-09-07', 'Independência do Brasil',     NULL),
               ('2026-10-12', 'Nossa Senhora Aparecida',     NULL),
               ('2026-11-02', 'Finados',                     NULL),
               ('2026-11-15', 'Proclamação da República',    NULL),
               ('2026-11-20', 'Consciência Negra',           NULL),
               ('2026-12-25', 'Natal',                       NULL),
               ('2026-11-30', 'Dia do Evangélico (DF)',      'Asa Sul')
       ) AS v (dt_feriado, ds_feriado, nm_campus)
  LEFT JOIN tb_campus c ON c.nm_campus = v.nm_campus;      -- LEFT: o campus NULL continua NULL


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 2 - CURSO, CURRÍCULO, DISCIPLINA, GRADE E PRÉ-REQUISITO

INSERT INTO tb_curso (cd_curso, nm_curso, ds_grau, qt_ch_total, id_campus)
SELECT v.cd_curso, v.nm_curso, v.ds_grau::tp_grau, v.qt_ch_total, c.id_campus
  FROM (VALUES ('CCO', 'Ciência da Computação',                 'bacharelado', 3200),
               ('SIS', 'Sistemas de Informação',                'bacharelado', 3000),
               ('ADS', 'Análise e Desenvolvimento de Sistemas', 'tecnologo',   2000)
       ) AS v (cd_curso, nm_curso, ds_grau, qt_ch_total)
  CROSS JOIN (SELECT id_campus FROM tb_campus WHERE nm_campus = 'Asa Sul') c;

-- Ciência da Computação tem duas grades: a de 2022 (inativa, os alunos mais antigos) e a de 2026
INSERT INTO tb_curriculo (id_curso, aa_vigencia, ic_ativo)
SELECT c.id_curso, v.aa_vigencia, v.ic_ativo
  FROM (VALUES ('CCO', 2022, FALSE), ('CCO', 2026, TRUE), ('SIS', 2026, TRUE), ('ADS', 2026, TRUE))
       AS v (cd_curso, aa_vigencia, ic_ativo)
  JOIN tb_curso c ON c.cd_curso = v.cd_curso;

-- qt_ch_total NÃO entra no INSERT: é coluna gerada, o banco soma teórica + prática
INSERT INTO tb_disciplina (cd_disciplina, nm_disciplina, qt_ch_teorica, qt_ch_pratica) VALUES
    ('CCO010', 'Algoritmos e Lógica de Programação', 40, 40),
    ('CCO011', 'Matemática Discreta',                80,  0),
    ('CCO012', 'Introdução à Computação',            40,  0),
    ('CCO013', 'Cálculo I',                          80,  0),
    ('CCO020', 'Estruturas de Dados',                40, 40),
    ('CCO021', 'Programação Orientada a Objetos',    40, 40),
    ('CCO022', 'Arquitetura de Computadores',        60, 20),
    ('CCO023', 'Cálculo II',                         80,  0),
    ('CCO030', 'Banco de Dados I',                   40, 40),
    ('CCO031', 'Teoria dos Grafos',                  60, 20),
    ('CCO032', 'Sistemas Operacionais',              60, 20),
    ('CCO033', 'Estatística e Probabilidade',        80,  0),
    ('CCO041', 'Engenharia de Software',             60, 20),
    ('CCO042', 'Redes de Computadores',              60, 20),
    ('CCO043', 'Teoria da Computação',               80,  0),
    ('CCO050', 'Inteligência Artificial',            60, 20),
    ('CCO051', 'Compiladores',                       60, 20),
    ('CCO052', 'Desenvolvimento Web',                40, 40),
    ('CCO053', 'Sistemas Distribuídos',              60, 20),
    ('CCO060', 'Projeto Integrador I',               20, 60),
    ('CCO061', 'Segurança da Informação',            60, 20),
    ('CCO070', 'Projeto Integrador II',              20, 60),
    ('CCO071', 'Trabalho de Conclusão de Curso',     20, 60),
    ('CCO072', 'Banco de Dados II',                  40, 40);

-- Grade de cada currículo: em qual semestre da grade (cd_periodo_grade) cada disciplina fica.
-- Todo pré-requisito de uma disciplina está num semestre ANTERIOR da mesma grade.
INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade, ds_tipo)
SELECT cu.id_curriculo, d.id_disciplina, v.cd_periodo_grade, v.ds_tipo::tp_tipo_disciplina
  FROM (VALUES
        -- Ciência da Computação, grade 2026 (8 semestres, 24 disciplinas)
        ('CCO', 2026, 'CCO010', 1, 'obrigatoria'), ('CCO', 2026, 'CCO011', 1, 'obrigatoria'),
        ('CCO', 2026, 'CCO012', 1, 'obrigatoria'), ('CCO', 2026, 'CCO013', 1, 'obrigatoria'),
        ('CCO', 2026, 'CCO020', 2, 'obrigatoria'), ('CCO', 2026, 'CCO021', 2, 'obrigatoria'),
        ('CCO', 2026, 'CCO022', 2, 'obrigatoria'), ('CCO', 2026, 'CCO023', 2, 'obrigatoria'),
        ('CCO', 2026, 'CCO030', 3, 'obrigatoria'), ('CCO', 2026, 'CCO031', 3, 'obrigatoria'),
        ('CCO', 2026, 'CCO032', 3, 'obrigatoria'), ('CCO', 2026, 'CCO033', 3, 'obrigatoria'),
        ('CCO', 2026, 'CCO072', 4, 'obrigatoria'), ('CCO', 2026, 'CCO041', 4, 'obrigatoria'),
        ('CCO', 2026, 'CCO042', 4, 'obrigatoria'), ('CCO', 2026, 'CCO043', 4, 'obrigatoria'),
        ('CCO', 2026, 'CCO050', 5, 'optativa'),    ('CCO', 2026, 'CCO051', 5, 'obrigatoria'),
        ('CCO', 2026, 'CCO052', 5, 'obrigatoria'), ('CCO', 2026, 'CCO053', 5, 'obrigatoria'),
        ('CCO', 2026, 'CCO060', 6, 'obrigatoria'), ('CCO', 2026, 'CCO061', 6, 'optativa'),
        ('CCO', 2026, 'CCO070', 7, 'obrigatoria'), ('CCO', 2026, 'CCO071', 8, 'obrigatoria'),
        -- Sistemas de Informação, grade 2026 (7 semestres, 13 disciplinas)
        ('SIS', 2026, 'CCO010', 1, 'obrigatoria'), ('SIS', 2026, 'CCO011', 1, 'obrigatoria'),
        ('SIS', 2026, 'CCO012', 1, 'obrigatoria'), ('SIS', 2026, 'CCO020', 2, 'obrigatoria'),
        ('SIS', 2026, 'CCO021', 2, 'obrigatoria'), ('SIS', 2026, 'CCO022', 2, 'obrigatoria'),
        ('SIS', 2026, 'CCO030', 3, 'obrigatoria'), ('SIS', 2026, 'CCO041', 3, 'obrigatoria'),
        ('SIS', 2026, 'CCO072', 4, 'obrigatoria'), ('SIS', 2026, 'CCO052', 4, 'obrigatoria'),
        ('SIS', 2026, 'CCO060', 5, 'obrigatoria'), ('SIS', 2026, 'CCO070', 6, 'obrigatoria'),
        ('SIS', 2026, 'CCO071', 7, 'obrigatoria'),
        -- Análise e Desenvolvimento de Sistemas, grade 2026 (5 semestres, 9 disciplinas)
        ('ADS', 2026, 'CCO010', 1, 'obrigatoria'), ('ADS', 2026, 'CCO012', 1, 'obrigatoria'),
        ('ADS', 2026, 'CCO020', 2, 'obrigatoria'), ('ADS', 2026, 'CCO021', 2, 'obrigatoria'),
        ('ADS', 2026, 'CCO030', 3, 'obrigatoria'), ('ADS', 2026, 'CCO041', 3, 'obrigatoria'),
        ('ADS', 2026, 'CCO072', 4, 'obrigatoria'), ('ADS', 2026, 'CCO052', 4, 'eletiva'),
        ('ADS', 2026, 'CCO060', 5, 'obrigatoria')
       ) AS v (cd_curso, aa_vigencia, cd_disciplina, cd_periodo_grade, ds_tipo)
  JOIN tb_curso       c  ON c.cd_curso = v.cd_curso
  JOIN tb_curriculo   cu ON cu.id_curso = c.id_curso AND cu.aa_vigencia = v.aa_vigencia
  JOIN tb_disciplina  d  ON d.cd_disciplina = v.cd_disciplina;

-- Grade antiga de Ciência da Computação (2022): é a de 2026 SEM Desenvolvimento Web e Segurança da Informação
INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, cd_periodo_grade, ds_tipo)
SELECT antigo.id_curriculo, cd.id_disciplina, cd.cd_periodo_grade, cd.ds_tipo
  FROM tb_curriculo_disciplina cd
  JOIN tb_curriculo novo   ON novo.id_curriculo = cd.id_curriculo AND novo.aa_vigencia = 2026
  JOIN tb_curso c          ON c.id_curso = novo.id_curso AND c.cd_curso = 'CCO'
  JOIN tb_curriculo antigo ON antigo.id_curso = c.id_curso AND antigo.aa_vigencia = 2022
  JOIN tb_disciplina d     ON d.id_disciplina = cd.id_disciplina
 WHERE d.cd_disciplina NOT IN ('CCO052', 'CCO061');

-- "A exige B": o par (disciplina, requisito). Forma cadeias de até 6 disciplinas (CCO010 > CCO021 > CCO041 >
-- CCO060 > CCO070 > CCO071): serve para a consulta recursiva da árvore de pré-requisitos.
INSERT INTO tb_pre_requisito (id_disciplina, id_disciplina_requisito)
SELECT d.id_disciplina, r.id_disciplina
  FROM (VALUES ('CCO020', 'CCO010'), ('CCO021', 'CCO010'), ('CCO022', 'CCO012'), ('CCO023', 'CCO013'),
               ('CCO030', 'CCO020'), ('CCO031', 'CCO020'), ('CCO031', 'CCO011'), ('CCO032', 'CCO022'),
               ('CCO033', 'CCO023'), ('CCO072', 'CCO030'), ('CCO041', 'CCO021'), ('CCO042', 'CCO032'),
               ('CCO043', 'CCO031'), ('CCO050', 'CCO031'), ('CCO050', 'CCO033'), ('CCO051', 'CCO043'),
               ('CCO051', 'CCO021'), ('CCO052', 'CCO021'), ('CCO052', 'CCO030'), ('CCO053', 'CCO042'),
               ('CCO053', 'CCO032'), ('CCO060', 'CCO041'), ('CCO061', 'CCO042'), ('CCO070', 'CCO060'),
               ('CCO071', 'CCO070')
       ) AS v (cd_disciplina, cd_requisito)
  JOIN tb_disciplina d ON d.cd_disciplina = v.cd_disciplina
  JOIN tb_disciplina r ON r.cd_disciplina = v.cd_requisito;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 3 - PROFESSOR, PERÍODO LETIVO E SALA

-- 32 professores com nomes montados a partir de duas listas. Fictícios.
INSERT INTO tb_professor (cd_matricula, nm_professor, ds_email, ds_titulacao)
SELECT 'P' || lpad(n::text, 4, '0'),
       (ARRAY['Ana','Bruno','Carla','Daniel','Eduarda','Felipe','Gabriela','Henrique','Isabela','João',
              'Karen','Lucas','Marina','Nicolas','Olívia','Pedro','Rafaela','Samuel','Tatiane','Vinícius',
              'Beatriz','Caio','Débora','Fernando','Giovana','Hugo','Larissa','Mateus','Natália','Otávio']
       )[1 + pg_temp.fn_sorteio('pn' || n, 30)]
       || ' ' ||
       (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Rodrigues','Almeida','Nascimento','Lima',
              'Araújo','Ribeiro','Carvalho','Gomes','Martins','Rocha','Barbosa','Moreira','Cardoso','Teixeira',
              'Correia','Mendes','Freitas','Ramos','Nunes','Pinto','Monteiro','Cavalcanti','Duarte','Campos']
       )[1 + pg_temp.fn_sorteio('ps' || n, 30)],
       'prof' || lpad(n::text, 3, '0') || '@exemplo.com.br',
       (ARRAY['especialista', 'mestre', 'doutor'])[1 + n % 3]::tp_titulacao
  FROM generate_series(1, 32) AS n;

-- 8 semestres letivos; o último (2026/2) é o semestre atual
INSERT INTO tb_periodo_letivo (aa_periodo, cd_semestre, dt_inicio, dt_fim) VALUES
    (2023, 1, '2023-02-06', '2023-06-30'), (2023, 2, '2023-08-07', '2023-12-15'),
    (2024, 1, '2024-02-05', '2024-06-28'), (2024, 2, '2024-08-05', '2024-12-13'),
    (2025, 1, '2025-02-03', '2025-06-27'), (2025, 2, '2025-08-04', '2025-12-12'),
    (2026, 1, '2026-02-02', '2026-06-26'), (2026, 2, '2026-08-03', '2026-12-11');

-- 10 salas "de aula" no campus Asa Sul (as turmas usam só estas), 1 auditório e 1 sala em Goiânia
INSERT INTO tb_sala (id_campus, cd_sala, qt_capacidade, ds_tipo)
SELECT c.id_campus, v.cd_sala, v.qt_capacidade, v.ds_tipo::tp_tipo_sala
  FROM (VALUES ('Asa Sul', 'A101', 50, 'teorica'),     ('Asa Sul', 'A102', 50, 'teorica'),
               ('Asa Sul', 'A103', 50, 'teorica'),     ('Asa Sul', 'A104', 50, 'teorica'),
               ('Asa Sul', 'A105', 50, 'teorica'),     ('Asa Sul', 'LAB1', 45, 'laboratorio'),
               ('Asa Sul', 'LAB2', 45, 'laboratorio'), ('Asa Sul', 'LAB3', 45, 'laboratorio'),
               ('Asa Sul', 'LAB4', 45, 'laboratorio'), ('Asa Sul', 'LAB5', 45, 'laboratorio'),
               ('Asa Sul', 'AUD1', 150, 'auditorio'),  ('Goiânia Centro', 'G101', 40, 'teorica')
       ) AS v (nm_campus, cd_sala, qt_capacidade, ds_tipo)
  JOIN tb_campus c ON c.nm_campus = v.nm_campus;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 4 - TURMA E HORÁRIO

-- Oferta: TODA disciplina é oferecida TODO semestre, em 8 seções (A a H).
-- n numera as 192 turmas de um semestre (24 disciplinas x 8 seções) e decide horário, sala e professor.
CREATE TEMP TABLE _oferta ON COMMIT DROP AS
SELECT d.id_disciplina,
       s.sec,
       chr(64 + s.sec)             AS cd_turma,          -- 65 = 'A'
       (d.k - 1) * 8 + s.sec       AS n
  FROM (SELECT id_disciplina, row_number() OVER (ORDER BY cd_disciplina)::int AS k FROM tb_disciplina) d
 CROSS JOIN generate_series(1, 8) AS s (sec);

-- Professor: (n mod 32) + 1. Duas turmas só dividem professor se n for igual módulo 25 (mesmo horário) E módulo 32
-- (mesmo professor), o que só aconteceria para n diferentes por múltiplos de 800: com 192 turmas, nunca.
-- Turno: sai da faixa de horário da turma (ver o INSERT de tb_turma_horario).
-- Vagas: 45, que cabe em todas as salas usadas (50 ou 45).
INSERT INTO tb_turma (cd_turma, id_disciplina, id_periodo_letivo, id_professor, ds_turno, qt_vagas)
SELECT o.cd_turma, o.id_disciplina, p.id_periodo_letivo, pr.id_professor,
       (CASE WHEN ((o.n - 1) % 25) / 5 < 2 THEN 'matutino'
             WHEN ((o.n - 1) % 25) / 5 < 4 THEN 'vespertino'
             ELSE 'noturno' END)::tp_turno,
       45
  FROM tb_periodo_letivo p
 CROSS JOIN _oferta o
  JOIN (SELECT id_professor, row_number() OVER (ORDER BY id_professor) AS rn FROM tb_professor) pr
    ON pr.rn = (o.n % 32) + 1
 ORDER BY p.dt_inicio, o.n;

-- Horário: cada turma tem UM encontro por semana, de 100 minutos. Em cada semestre existem 25 "janelas"
-- (5 dias x 5 horários) e a turma n ocupa a janela (n-1) mod 25. A sala vem do grupo ((n-1) / 25):
-- turmas na mesma janela ficam em grupos (salas) diferentes, então o EXCLUDE de choque de sala nunca dispara.
INSERT INTO tb_turma_horario (id_turma, id_sala, id_periodo_letivo, dd_semana, hr_inicio, hr_fim)
SELECT t.id_turma, s.id_sala, t.id_periodo_letivo,
       ((o.n - 1) % 25) % 5 + 1,                                                        -- dia: 1 (seg) a 5 (sex)
       (ARRAY['08:00','10:00','14:00','16:00','19:00'])[((o.n - 1) % 25) / 5 + 1]::time,
       (ARRAY['08:00','10:00','14:00','16:00','19:00'])[((o.n - 1) % 25) / 5 + 1]::time + INTERVAL '100 minutes'
  FROM tb_turma t
  JOIN _oferta o ON o.id_disciplina = t.id_disciplina AND o.cd_turma = t.cd_turma
  JOIN (SELECT id_sala, row_number() OVER (ORDER BY id_sala) AS rn
          FROM tb_sala
         WHERE ds_tipo <> 'auditorio'
           AND id_campus = (SELECT id_campus FROM tb_campus WHERE nm_campus = 'Asa Sul')) s
    ON s.rn = ((o.n - 1) / 25) % 10 + 1;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 5 - ALUNO

-- Numera os períodos de 1 (2023/1) a 8 (2026/2)
CREATE TEMP TABLE _periodo_idx ON COMMIT DROP AS
SELECT id_periodo_letivo, dt_inicio, row_number() OVER (ORDER BY dt_inicio)::int AS idx
  FROM tb_periodo_letivo;

-- Plano da carga: para cada aluno (1 a 2000), curso, semestre da grade em que ele está agora (s), seção e grade.
--   i   = número do aluno             j = posição do aluno dentro do curso
--   s   = semestre da grade (CCO 1-8, SIS 1-7, ADS 1-5), distribuído em rodízio: todos os semestres ficam
--         com o mesmo número de alunos
--   sec = seção (1 a 8 = A a H): a "rodada" j / n_sem decide a seção, então cada (curso, semestre) reparte
--         os alunos igualmente entre as 8 seções e nenhuma turma passa das 45 vagas
--   ic_ativo = 1 em cada 23 alunos do curso evadiu (ic_ativo FALSE)
--   aa_curriculo = metade dos alunos de CCO do 7º/8º semestre ainda está na grade 2022
CREATE TEMP TABLE _plano ON COMMIT DROP AS
WITH g AS (
    SELECT i,
           CASE WHEN i % 10 < 6 THEN 'CCO' WHEN i % 10 < 8 THEN 'SIS' ELSE 'ADS' END AS cd_curso
      FROM generate_series(1, 2000) AS i
), h AS (
    SELECT g.*,
           row_number() OVER (PARTITION BY cd_curso ORDER BY i)                  AS j,
           CASE cd_curso WHEN 'CCO' THEN 8 WHEN 'SIS' THEN 7 ELSE 5 END          AS n_sem
      FROM g
)
SELECT i, j, cd_curso,
       ((j - 1) % n_sem + 1)::int                                                AS s,
       (((j - 1) / n_sem) % 8 + 1)::int                                          AS sec,
       (j % 23 <> 0)                                                             AS ic_ativo,
       CASE WHEN cd_curso = 'CCO' AND (j - 1) % n_sem + 1 >= 7 AND j % 2 = 0
            THEN 2022 ELSE 2026 END                                              AS aa_curriculo
  FROM h;

-- RA = 26 + número com 6 dígitos; CPF = 2026 + número com 7 dígitos (obviamente falso: não é CPF de ninguém);
-- ingresso = 45 dias antes do início do 1º semestre do aluno; nascimento até 31/12/2007, assim a
-- regra "ninguém ingressa com menos de 14 anos" (ck_aluno_datas) sempre vale.
INSERT INTO tb_aluno (cd_matricula, nm_aluno, cd_cpf, ds_email, dt_nascimento, id_curso, id_curriculo,
                      dt_ingresso, ic_ativo)
SELECT '26' || lpad(pl.i::text, 6, '0'),
       (ARRAY['Ana','Bruno','Carla','Daniel','Eduarda','Felipe','Gabriela','Henrique','Isabela','João',
              'Karen','Lucas','Marina','Nicolas','Olívia','Pedro','Rafaela','Samuel','Tatiane','Vinícius',
              'Beatriz','Caio','Débora','Fernando','Giovana','Hugo','Larissa','Mateus','Natália','Otávio']
       )[1 + pg_temp.fn_sorteio('an' || pl.i, 30)]
       || ' ' ||
       (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Rodrigues','Almeida','Nascimento','Lima',
              'Araújo','Ribeiro','Carvalho','Gomes','Martins','Rocha','Barbosa','Moreira','Cardoso','Teixeira',
              'Correia','Mendes','Freitas','Ramos','Nunes','Pinto','Monteiro','Cavalcanti','Duarte','Campos']
       )[1 + pg_temp.fn_sorteio('a1' || pl.i, 30)]
       || ' ' ||
       (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Rodrigues','Almeida','Nascimento','Lima',
              'Araújo','Ribeiro','Carvalho','Gomes','Martins','Rocha','Barbosa','Moreira','Cardoso','Teixeira',
              'Correia','Mendes','Freitas','Ramos','Nunes','Pinto','Monteiro','Cavalcanti','Duarte','Campos']
       )[1 + pg_temp.fn_sorteio('a2' || pl.i, 30)],
       '2026' || lpad(pl.i::text, 7, '0'),
       'aluno' || lpad(pl.i::text, 4, '0') || '@exemplo.com.br',
       DATE '2007-12-31' - pg_temp.fn_sorteio('nasc' || pl.i, 8000),
       c.id_curso, cu.id_curriculo,
       pi.dt_inicio - 45,
       pl.ic_ativo
  FROM _plano pl
  JOIN tb_curso c        ON c.cd_curso = pl.cd_curso
  JOIN tb_curriculo cu   ON cu.id_curso = c.id_curso AND cu.aa_vigencia = pl.aa_curriculo
  JOIN _periodo_idx pi   ON pi.idx = 9 - pl.s            -- 1º semestre do aluno = 8 - (s - 1)
 ORDER BY pl.i;


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 6 - MATRÍCULA

-- Cada aluno se matricula, em cada semestre da grade (k) de 1 até o atual (s), nas disciplinas daquele semestre.
-- O semestre da grade k aconteceu no período 8 - (s - k): o semestre atual (k = s) é o período 8 (2026/2).
--   períodos 1 a 7 -> 'concluida'
--   período 8      -> 'ativa'; ou 'cancelada' (aluno evadido); ou 'trancada' (1 em 25)
INSERT INTO tb_matricula (id_aluno, id_turma, dt_matricula, ds_status)
SELECT a.id_aluno, t.id_turma,
       -- matrícula feita de 1 a 25 dias antes do início do semestre, em horário comercial
       (p.dt_inicio - (1 + pg_temp.fn_sorteio('dm' || pl.i || '-' || t.id_turma, 25)))::timestamp
         + make_interval(hours => 8 + pg_temp.fn_sorteio('hm' || pl.i || '-' || t.id_turma, 10),
                         mins  => pg_temp.fn_sorteio('mm' || pl.i || '-' || t.id_turma, 60)),
       (CASE WHEN p.idx < 8 THEN 'concluida'
             WHEN NOT pl.ic_ativo THEN 'cancelada'
             WHEN pg_temp.fn_sorteio('st' || pl.i || '-' || t.id_turma, 25) = 0 THEN 'trancada'
             ELSE 'ativa' END)::tp_status_matricula
  FROM _plano pl
  JOIN tb_aluno a                  ON a.cd_matricula = '26' || lpad(pl.i::text, 6, '0')
  JOIN tb_curriculo_disciplina cd  ON cd.id_curriculo = a.id_curriculo AND cd.cd_periodo_grade <= pl.s
  JOIN _periodo_idx p              ON p.idx = 8 - (pl.s - cd.cd_periodo_grade)
  JOIN tb_turma t                  ON t.id_disciplina = cd.id_disciplina
                                  AND t.id_periodo_letivo = p.id_periodo_letivo
                                  AND t.cd_turma = chr(64 + pl.sec)
 ORDER BY pl.i, p.idx, t.id_turma;

-- Vira "última vaga": a turma de Banco de Dados II (CCO072) de 2026/2, seção A, fica com 1 vaga livre.
UPDATE tb_turma t
   SET qt_vagas = (SELECT count(*) FROM tb_matricula m WHERE m.id_turma = t.id_turma AND m.ds_status = 'ativa') + 1
  FROM tb_disciplina d, tb_periodo_letivo p
 WHERE d.id_disciplina = t.id_disciplina AND p.id_periodo_letivo = t.id_periodo_letivo
   AND d.cd_disciplina = 'CCO072' AND p.aa_periodo = 2026 AND p.cd_semestre = 2 AND t.cd_turma = 'A';

-- Log de auditoria: as matrículas trancadas/canceladas "foram alteradas pela secretaria". Sem FK, como no modelo.
INSERT INTO tb_log_matricula (id_matricula, ds_acao, dt_ocorrencia, nm_usuario, ds_detalhe)
SELECT m.id_matricula, 'UPDATE', m.dt_matricula + INTERVAL '20 days', 'secretaria',
       jsonb_build_object('campo', 'ds_status', 'de', 'ativa', 'para', m.ds_status::text)
  FROM tb_matricula m
 WHERE m.ds_status IN ('trancada', 'cancelada');


------------------------------------------------------------------------------------------------------------------------
-- BLOCO 7 - HISTÓRICO

-- Só 'concluida' e 'ativa' têm histórico (trancada e cancelada ficam sem: é o (0,1) de tb_historico).
-- qt_media_final é coluna GERADA: não entra no INSERT. Para escolher a situação, a conta da média é repetida aqui
-- (a mesma fórmula do modelo_fisico_v1.sql) e a ck_historico_* garante que a situação bate com os números.
--   disciplina "folha" = ninguém a exige como pré-requisito: só nelas há reprovação (notas e frequência mais baixas)
--   'concluida': A1 e A2 lançadas; P3 só para folha com média abaixo de 5 (1 em cada 3 deles)
--   'ativa'    : só A1 lançada, média ainda NULL, situação 'cursando'
INSERT INTO tb_historico (id_matricula, qt_nota_a1, qt_nota_a2, qt_nota_p3, pc_frequencia, ds_situacao)
WITH base AS (
    SELECT m.id_matricula, m.ds_status,
           NOT EXISTS (SELECT 1 FROM tb_pre_requisito pr WHERE pr.id_disciplina_requisito = t.id_disciplina) AS ic_folha
      FROM tb_matricula m
      JOIN tb_turma t ON t.id_turma = m.id_turma
     WHERE m.ds_status IN ('concluida', 'ativa')
), notas AS (
    SELECT b.*,
           LEAST(10, CASE WHEN ic_folha THEN 3.0 ELSE 5.5 END
                     + pg_temp.fn_sorteio('n1' || id_matricula, CASE WHEN ic_folha THEN 71 ELSE 45 END) / 10.0) AS a1,
           LEAST(10, CASE WHEN ic_folha THEN 3.0 ELSE 5.5 END
                     + pg_temp.fn_sorteio('n2' || id_matricula, CASE WHEN ic_folha THEN 71 ELSE 45 END) / 10.0) AS a2,
           CASE WHEN ds_status = 'ativa'  THEN 70 + pg_temp.fn_sorteio('fq' || id_matricula, 31)
                WHEN ic_folha             THEN 70 + pg_temp.fn_sorteio('fq' || id_matricula, 31)
                ELSE                           80 + pg_temp.fn_sorteio('fq' || id_matricula, 21) END AS freq
      FROM base b
), com_p3 AS (
    SELECT n.*,
           CASE WHEN ds_status = 'concluida' AND ic_folha
                 AND ROUND(0.4 * a1 + 0.6 * a2, 2) < 5
                 AND pg_temp.fn_sorteio('p3q' || id_matricula, 3) = 0
                THEN LEAST(10, 5.0 + pg_temp.fn_sorteio('p3n' || id_matricula, 50) / 10.0) END AS p3
      FROM notas n
), final AS (
    SELECT c.*,
           ROUND(GREATEST(0.4 * a1 + 0.6 * a2, 0.4 * p3 + 0.6 * a2, 0.4 * a1 + 0.6 * p3), 2) AS media
      FROM com_p3 c
)
SELECT id_matricula,
       a1,
       CASE WHEN ds_status = 'concluida' THEN a2 END,
       p3,
       freq,
       (CASE WHEN ds_status = 'ativa' THEN 'cursando'
             WHEN freq < 75          THEN 'reprovado_falta'
             WHEN media >= 5         THEN 'aprovado'
             ELSE                         'reprovado_nota' END)::tp_situacao
  FROM final
 ORDER BY id_matricula;

COMMIT;

-- Estatísticas novas para o planejador: sem isto o EXPLAIN do indices_v1.sql usaria números velhos
ANALYZE tb_cidade, tb_campus, tb_feriado, tb_curso, tb_curriculo, tb_disciplina, tb_curriculo_disciplina,
        tb_pre_requisito, tb_professor, tb_periodo_letivo, tb_sala, tb_turma, tb_turma_horario,
        tb_aluno, tb_matricula, tb_historico, tb_log_matricula;


------------------------------------------------------------------------------------------------------------------------
--CONFERÊNCIA
SELECT item, valor, esperado
  FROM (
    SELECT 1 AS ord, 'tb_aluno'      AS item, count(*)::text AS valor, 'mínimo 100'  AS esperado FROM tb_aluno
    UNION ALL SELECT 2,  'tb_turma',        count(*)::text, 'mínimo 6'   FROM tb_turma
    UNION ALL SELECT 3,  'tb_matricula',    count(*)::text, 'mínimo 300' FROM tb_matricula
    UNION ALL SELECT 4,  'tb_historico',    count(*)::text, 'uma por matrícula concluída ou ativa' FROM tb_historico
    UNION ALL SELECT 5,  'turmas em 2026/2', count(*)::text, '192'
             FROM tb_turma t JOIN tb_periodo_letivo p USING (id_periodo_letivo)
            WHERE p.aa_periodo = 2026 AND p.cd_semestre = 2
    UNION ALL SELECT 6,  'matrículas ativas em 2026/2', count(*)::text, 'só as ativas contam vaga'
             FROM tb_matricula WHERE ds_status = 'ativa'
    UNION ALL SELECT 7,  'maior ocupação de uma turma (ativas)', max(qt)::text, 'no máximo 45 (as vagas)'
             FROM (SELECT count(*) AS qt FROM tb_matricula WHERE ds_status = 'ativa' GROUP BY id_turma) x
    UNION ALL SELECT 8,  'vagas livres em CCO072/2026-2/A', (t.qt_vagas - count(*))::text, '1 (a última vaga)'
             FROM tb_turma t
             JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina AND d.cd_disciplina = 'CCO072'
             JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo AND p.aa_periodo = 2026 AND p.cd_semestre = 2
             JOIN tb_matricula m ON m.id_turma = t.id_turma AND m.ds_status = 'ativa'
            WHERE t.cd_turma = 'A'
            GROUP BY t.qt_vagas
  ) r
 ORDER BY ord;
