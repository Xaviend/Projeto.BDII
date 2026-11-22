/*
Autor: Arthur Coupê - Administração e Operação
Objetivo: as 10 consultas comentadas do Marco 1. As 5 exigidas pelo enunciado são a 3, 4, 5, 6 e 7:
            3  junção externa (LEFT JOIN) com agregação
            4  recursiva: árvore de pré-requisitos de uma disciplina
            5  recursiva: disciplinas que um aluno já pode cursar (liberadas)
            6  função de janela com ranking e percentil
            7  função de janela com LAG
          As outras 5 cobrem o que a arguição pede para explicar com exemplo do projeto (perguntas 13 e 15):
            1  "selecione 10 alunos" (a pegadinha do ORDER BY)
            2  INNER JOIN
            8  SELF JOIN
            9  subconsulta (NOT EXISTS) com CTE
            10 UNION ALL x UNION

Como rodar:
  - rodar DEPOIS do 01_modelo_fisico_v1.sql e do 03_carga_v1.sql (os dados são sempre os mesmos, então os resultados
    também);
  - só lê (SELECT), não altera nada. Cada consulta pode ser selecionada e rodada sozinha com F5
    (o SET search_path do começo precisa ter rodado uma vez na aba).

"Semestre atual" nas consultas = o período letivo mais recente cadastrado (2026/2), e não a data de hoje:
assim o resultado é o mesmo em qualquer dia em que o professor rodar.

06_consultas_v1
*/
------------------------------------------------------------------------------------------------------------------------
-- Faz a conferência do banco (esperado: matricula)
SELECT current_database();
SET search_path TO projeto_bd2, public;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 1 - 10 ALUNOS (pergunta 13 da arguição)
-- Pergunta: quais são os 10 primeiros alunos em ordem alfabética?
-- A pegadinha: "SELECT * FROM tb_aluno LIMIT 10" devolve 10 linhas quaisquer. Sem ORDER BY o banco não promete
-- ordem nenhuma: pode mudar depois de um UPDATE, de um VACUUM ou de um plano diferente.
-- O desempate por cd_matricula garante a mesma resposta mesmo com dois alunos de nome igual.

SELECT cd_matricula, nm_aluno, dt_ingresso
  FROM tb_aluno
 ORDER BY nm_aluno, cd_matricula
 LIMIT 10;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 2 - INNER JOIN
-- Pergunta: qual é a grade horária do aluno 26000005 no semestre atual (disciplina, dia, horário, sala, professor)?
-- INNER JOIN só devolve a linha quando existe o par dos dois lados. Aqui é o que queremos: matrícula sem turma
-- ou turma sem horário não entra na grade.
-- Filtro ds_status = 'ativa': matrícula trancada ou cancelada não ocupa horário.

SELECT d.cd_disciplina,
       d.nm_disciplina,
       (ARRAY['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'])[th.dd_semana] AS dia,
       to_char(th.hr_inicio, 'HH24:MI') || '-' || to_char(th.hr_fim, 'HH24:MI') AS horario,
       s.cd_sala,
       pr.nm_professor
  FROM tb_aluno a
  JOIN tb_matricula m      ON m.id_aluno = a.id_aluno AND m.ds_status = 'ativa'
  JOIN tb_turma t          ON t.id_turma = m.id_turma
  JOIN tb_disciplina d     ON d.id_disciplina = t.id_disciplina
  JOIN tb_turma_horario th ON th.id_turma = t.id_turma
  JOIN tb_sala s           ON s.id_sala = th.id_sala
  JOIN tb_professor pr     ON pr.id_professor = t.id_professor
 WHERE a.cd_matricula = '26000005'
   AND t.id_periodo_letivo = (SELECT id_periodo_letivo FROM tb_periodo_letivo
                               ORDER BY aa_periodo DESC, cd_semestre DESC LIMIT 1)
 ORDER BY th.dd_semana, th.hr_inicio;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 3 - JUNÇÃO EXTERNA COM AGREGAÇÃO (exigida)
-- Pergunta: quantos cursos e quantos alunos ativos tem cada campus, inclusive campus sem nenhum curso?
-- LEFT JOIN mantém todos os campus, mesmo sem curso: o campus Goiânia Centro aparece com 0.
-- Com INNER JOIN ele sumiria do resultado, e é justamente o caso que a direção quer ver.
-- Dois cuidados:
--   - count(c.id_curso) e não count(*): count(*) conta a linha do campus vazio (que tem curso NULL) e daria 1;
--     count(coluna) não conta NULL e dá 0;
--   - o filtro "aluno ativo" vai no ON do LEFT JOIN. Se fosse no WHERE, viraria INNER JOIN na prática:
--     o campus sem aluno tem a.ic_ativo NULL, o WHERE descarta e o campus some de novo.

SELECT cp.nm_campus,
       ci.nm_cidade || '/' || ci.sg_uf     AS cidade,
       count(DISTINCT c.id_curso)          AS qt_cursos,
       count(a.id_aluno)                   AS qt_alunos_ativos
  FROM tb_campus cp
  JOIN tb_cidade ci     ON ci.id_cidade = cp.id_cidade
  LEFT JOIN tb_curso c  ON c.id_campus = cp.id_campus
  LEFT JOIN tb_aluno a  ON a.id_curso = c.id_curso AND a.ic_ativo
 GROUP BY cp.id_campus, ci.id_cidade
 ORDER BY qt_alunos_ativos DESC, cp.nm_campus;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 4 - RECURSIVA: ÁRVORE DE PRÉ-REQUISITOS (exigida)
-- Pergunta: para cursar Compiladores (CCO051), o que o aluno precisa ter feito antes, direta e indiretamente?
-- WITH RECURSIVE tem duas partes ligadas por UNION ALL:
--   - a âncora: os pré-requisitos diretos de CCO051 (nível 1);
--   - a parte recursiva: os pré-requisitos de cada requisito já achado (nível 2, 3...). Ela roda de novo sobre as
--     linhas novas até não aparecer nenhuma.
-- caminho guarda as disciplinas já visitadas no ramo. "NOT ... = ANY(caminho)" impede laço infinito se alguém
-- cadastrar um ciclo (A exige B e B exige A); a restrição da tabela só impede a disciplina exigir ela mesma.
-- O mesmo requisito pode aparecer em dois ramos (CCO010 vem por CCO021 e por CCO020): é uma árvore, não uma lista.

WITH RECURSIVE arvore (id_disciplina, nivel, caminho) AS (
    SELECT pr.id_disciplina_requisito, 1, ARRAY[d.id_disciplina, pr.id_disciplina_requisito]
      FROM tb_disciplina d
      JOIN tb_pre_requisito pr ON pr.id_disciplina = d.id_disciplina
     WHERE d.cd_disciplina = 'CCO051'
    UNION ALL
    SELECT pr.id_disciplina_requisito, a.nivel + 1, a.caminho || pr.id_disciplina_requisito
      FROM arvore a
      JOIN tb_pre_requisito pr ON pr.id_disciplina = a.id_disciplina
     WHERE NOT pr.id_disciplina_requisito = ANY (a.caminho)
)
SELECT a.nivel,
       repeat('    ', a.nivel - 1) || d.cd_disciplina || ' - ' || d.nm_disciplina AS pre_requisito,
       (SELECT string_agg(x.cd_disciplina, ' <- ' ORDER BY u.pos)
          FROM unnest(a.caminho) WITH ORDINALITY AS u(id, pos)
          JOIN tb_disciplina x ON x.id_disciplina = u.id)                     AS caminho
  FROM arvore a
  JOIN tb_disciplina d ON d.id_disciplina = a.id_disciplina
 ORDER BY a.caminho;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 5 - RECURSIVA: DISCIPLINAS LIBERADAS PARA O ALUNO (exigida)
-- Pergunta: quais disciplinas do currículo o aluno 26000005 (5º semestre de CCO) já pode cursar?
-- Liberada = está no currículo dele, ele ainda não foi aprovado nem está cursando, e TODOS os pré-requisitos da
-- cadeia (diretos e indiretos) já foram aprovados.
-- A recursão monta a cadeia completa de cada disciplina (a mesma ideia da consulta 4, mas para todas de uma vez).
-- A disciplina sem pré-requisito nenhum entra pelo LEFT JOIN (cadeia vazia = liberada).
-- Reprovação conta como "não aprovado": a disciplina reprovada volta a aparecer como liberada para refazer.
-- Resultado esperado: CCO072 (ele reprovou por nota em 2026/1 e pode refazer), CCO060 e CCO061 (os pré-requisitos
-- já foram aprovados). As 4 de 2026/2 ficam fora porque ele está cursando.

WITH RECURSIVE
cadeia (id_disciplina, id_requisito, caminho) AS (
    SELECT pr.id_disciplina, pr.id_disciplina_requisito, ARRAY[pr.id_disciplina, pr.id_disciplina_requisito]
      FROM tb_pre_requisito pr
     WHERE pr.ds_vinculo = 'pre_requisito'
    UNION ALL
    SELECT c.id_disciplina, pr.id_disciplina_requisito, c.caminho || pr.id_disciplina_requisito
      FROM cadeia c
      JOIN tb_pre_requisito pr ON pr.id_disciplina = c.id_requisito
     WHERE pr.ds_vinculo = 'pre_requisito'
       AND NOT pr.id_disciplina_requisito = ANY (c.caminho)
),
aluno AS (
    SELECT id_aluno, id_curriculo FROM tb_aluno WHERE cd_matricula = '26000005'
),
cursadas AS (            -- disciplinas aprovadas ou em andamento
    SELECT t.id_disciplina, h.ds_situacao
      FROM aluno al
      JOIN tb_matricula m ON m.id_aluno = al.id_aluno
      JOIN tb_historico h ON h.id_matricula = m.id_matricula
      JOIN tb_turma t     ON t.id_turma = m.id_turma
     WHERE h.ds_situacao IN ('aprovado', 'cursando')
)
SELECT cd.cd_periodo_grade                     AS semestre_da_grade,
       d.cd_disciplina,
       d.nm_disciplina,
       cd.ds_tipo,
       count(DISTINCT c.id_requisito)          AS qt_pre_requisitos_na_cadeia
  FROM aluno al
  JOIN tb_curriculo_disciplina cd ON cd.id_curriculo = al.id_curriculo
  JOIN tb_disciplina d            ON d.id_disciplina = cd.id_disciplina
  LEFT JOIN cadeia c              ON c.id_disciplina = d.id_disciplina
 WHERE NOT EXISTS (SELECT 1 FROM cursadas x WHERE x.id_disciplina = d.id_disciplina)
 GROUP BY cd.cd_periodo_grade, d.id_disciplina, cd.ds_tipo
HAVING count(c.id_requisito) FILTER (
           WHERE c.id_requisito NOT IN (SELECT id_disciplina FROM cursadas WHERE ds_situacao = 'aprovado')) = 0
 ORDER BY cd.cd_periodo_grade, d.cd_disciplina;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 6 - FUNÇÃO DE JANELA COM RANKING E PERCENTIL (exigida)
-- Pergunta: quem são os 5 melhores alunos de cada curso pelo coeficiente de rendimento (CR), e em que percentil
--           cada um está?
-- CR = média das médias finais pesada pela carga horária, só de disciplinas já encerradas (sem "cursando").
-- Função de janela calcula olhando as outras linhas SEM juntar as linhas num grupo (o GROUP BY juntaria):
--   RANK() OVER (PARTITION BY curso ORDER BY cr DESC) = posição dentro do curso. Empate recebe a mesma posição e
--                                                       pula a seguinte (1, 2, 2, 4);
--   PERCENT_RANK() = (posição - 1) / (alunos do curso - 1): 0 é o primeiro e 1 o último.
--                    "top %" = em que fatia do curso o aluno está;
--   percentile_cont(0.5) = mediana do CR do curso (o valor do meio). Ela é função de agregação, não de janela,
--                          por isso vai numa CTE separada.
-- O filtro "posicao <= 5" fica fora (na consulta de fora): WHERE roda antes da janela, então não enxerga RANK.

WITH cr AS (
    SELECT a.id_aluno, a.cd_matricula, a.nm_aluno, c.cd_curso,
           round(sum(h.qt_media_final * d.qt_ch_total) / sum(d.qt_ch_total), 2) AS qt_cr,
           count(*) AS qt_disciplinas
      FROM tb_aluno a
      JOIN tb_curso c       ON c.id_curso = a.id_curso
      JOIN tb_matricula m   ON m.id_aluno = a.id_aluno
      JOIN tb_historico h   ON h.id_matricula = m.id_matricula
      JOIN tb_turma t       ON t.id_turma = m.id_turma
      JOIN tb_disciplina d  ON d.id_disciplina = t.id_disciplina
     WHERE h.ds_situacao <> 'cursando'
     GROUP BY a.id_aluno, c.id_curso
    HAVING count(*) >= 8          -- pelo menos 2 semestres encerrados: calouro com 2 notas não lidera o ranking
),
mediana AS (
    SELECT cd_curso, percentile_cont(0.5) WITHIN GROUP (ORDER BY qt_cr) AS qt_mediana_cr
      FROM cr
     GROUP BY cd_curso
),
ranking AS (
    SELECT cr.*,
           RANK()         OVER (PARTITION BY cd_curso ORDER BY qt_cr DESC) AS posicao,
           PERCENT_RANK() OVER (PARTITION BY cd_curso ORDER BY qt_cr DESC) AS pc_rank,
           count(*)       OVER (PARTITION BY cd_curso)                     AS qt_alunos_curso
      FROM cr
)
SELECT r.cd_curso, r.posicao, r.cd_matricula, r.nm_aluno, r.qt_cr, r.qt_disciplinas,
       'top ' || round((100 * r.pc_rank)::numeric, 1) || '%' AS percentil,
       r.qt_alunos_curso,
       round(m.qt_mediana_cr::numeric, 2)          AS qt_mediana_cr_curso
  FROM ranking r
  JOIN mediana m ON m.cd_curso = r.cd_curso
 WHERE r.posicao <= 5
 ORDER BY r.cd_curso, r.posicao, r.cd_matricula;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 7 - FUNÇÃO DE JANELA COM LAG (exigida)
-- Pergunta: como o rendimento do aluno 26000012 evoluiu semestre a semestre? Melhorou ou piorou em relação ao
--           semestre anterior?
-- LAG(valor) OVER (ORDER BY período) devolve o valor da linha ANTERIOR na ordem da janela. No primeiro semestre
-- não existe anterior e o LAG devolve NULL (por isso a variação do primeiro fica vazia).
-- Sem LAG seria preciso juntar a tabela com ela mesma deslocada de um semestre.

WITH por_semestre AS (
    SELECT p.aa_periodo, p.cd_semestre,
           p.aa_periodo || '/' || p.cd_semestre AS ds_periodo,
           count(*)                                                   AS qt_disciplinas,
           count(*) FILTER (WHERE h.ds_situacao = 'aprovado')         AS qt_aprovadas,
           round(avg(h.qt_media_final), 2)                            AS qt_media_semestre
      FROM tb_aluno a
      JOIN tb_matricula m      ON m.id_aluno = a.id_aluno
      JOIN tb_historico h      ON h.id_matricula = m.id_matricula
      JOIN tb_turma t          ON t.id_turma = m.id_turma
      JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
     WHERE a.cd_matricula = '26000012'
       AND h.ds_situacao <> 'cursando'
     GROUP BY p.id_periodo_letivo
)
SELECT ds_periodo, qt_disciplinas, qt_aprovadas, qt_media_semestre,
       LAG(qt_media_semestre) OVER (ORDER BY aa_periodo, cd_semestre)                     AS qt_media_anterior,
       qt_media_semestre - LAG(qt_media_semestre) OVER (ORDER BY aa_periodo, cd_semestre) AS qt_variacao,
       CASE
           WHEN LAG(qt_media_semestre) OVER (ORDER BY aa_periodo, cd_semestre) IS NULL THEN 'primeiro semestre'
           WHEN qt_media_semestre > LAG(qt_media_semestre) OVER (ORDER BY aa_periodo, cd_semestre) THEN 'melhorou'
           WHEN qt_media_semestre < LAG(qt_media_semestre) OVER (ORDER BY aa_periodo, cd_semestre) THEN 'piorou'
           ELSE 'igual'
       END AS ds_tendencia
  FROM por_semestre
 ORDER BY aa_periodo, cd_semestre;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 8 - SELF JOIN
-- Pergunta: quais colegas mais dividiram turma com o aluno 26000012 durante o curso?
-- SELF JOIN = a mesma tabela duas vezes, com apelidos diferentes: "eu" é a matrícula do 26000012 e "colega" é
-- outra matrícula na MESMA turma. A condição colega.id_aluno <> eu.id_aluno tira ele mesmo do resultado.

SELECT ac.cd_matricula,
       ac.nm_aluno,
       count(*) AS qt_turmas_juntos
  FROM tb_aluno a
  JOIN tb_matricula eu     ON eu.id_aluno = a.id_aluno
  JOIN tb_matricula colega ON colega.id_turma = eu.id_turma
                          AND colega.id_aluno <> eu.id_aluno
  JOIN tb_aluno ac         ON ac.id_aluno = colega.id_aluno
 WHERE a.cd_matricula = '26000012'
 GROUP BY ac.id_aluno
 ORDER BY qt_turmas_juntos DESC, ac.cd_matricula
 LIMIT 5;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 9 - SUBCONSULTA (NOT EXISTS) COM CTE
-- Pergunta: quais alunos ativos não têm nenhuma matrícula ativa no semestre atual (risco de evasão)?
-- A CTE (WITH) dá nome ao "semestre atual" e deixa a consulta principal legível.
-- NOT EXISTS é uma subconsulta correlacionada: para cada aluno, procura uma matrícula ativa dele no semestre.
-- Prefira NOT EXISTS a NOT IN: se a subconsulta do NOT IN devolver um NULL, o NOT IN não devolve linha nenhuma
-- (comparação com NULL é "desconhecido"). NOT EXISTS não tem esse problema.

WITH semestre_atual AS (
    SELECT id_periodo_letivo
      FROM tb_periodo_letivo
     ORDER BY aa_periodo DESC, cd_semestre DESC
     LIMIT 1
)
SELECT a.cd_matricula,
       a.nm_aluno,
       c.cd_curso,
       (SELECT string_agg(DISTINCT m.ds_status::text, ', ')            -- subconsulta escalar na lista do SELECT
          FROM tb_matricula m
          JOIN tb_turma t ON t.id_turma = m.id_turma
         WHERE m.id_aluno = a.id_aluno
           AND t.id_periodo_letivo = (SELECT id_periodo_letivo FROM semestre_atual)) AS status_no_semestre
  FROM tb_aluno a
  JOIN tb_curso c ON c.id_curso = a.id_curso
 WHERE a.ic_ativo
   AND NOT EXISTS (SELECT 1
                     FROM tb_matricula m
                     JOIN tb_turma t ON t.id_turma = m.id_turma
                    WHERE m.id_aluno = a.id_aluno
                      AND m.ds_status = 'ativa'
                      AND t.id_periodo_letivo = (SELECT id_periodo_letivo FROM semestre_atual))
 ORDER BY c.cd_curso, a.cd_matricula;


------------------------------------------------------------------------------------------------------------------------
-- CONSULTA 10 - UNION ALL x UNION
-- Pergunta: para quem mandar o comunicado da semana de provas de Banco de Dados II (CCO072) no semestre atual?
--           (alunos com matrícula ativa na disciplina + professores que dão aula nela)
-- UNION ALL junta os dois resultados um embaixo do outro. As duas partes precisam ter as mesmas colunas, na mesma
-- ordem e com tipos compatíveis.
-- UNION (sem ALL) também tiraria as linhas repetidas, mas para isso ordena tudo e custa mais. Aqui não existe
-- repetição (a coluna "papel" já separa aluno de professor), então UNION ALL é o certo.
-- A segunda consulta abaixo mostra a diferença com uma lista onde existe repetição.

WITH turmas_bd2 AS (
    SELECT t.id_turma, t.id_professor
      FROM tb_turma t
      JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
     WHERE d.cd_disciplina = 'CCO072'
       AND t.id_periodo_letivo = (SELECT id_periodo_letivo FROM tb_periodo_letivo
                                   ORDER BY aa_periodo DESC, cd_semestre DESC LIMIT 1)
)
SELECT 'aluno' AS papel, a.nm_aluno AS nome, a.ds_email
  FROM turmas_bd2 tb
  JOIN tb_matricula m ON m.id_turma = tb.id_turma AND m.ds_status = 'ativa'
  JOIN tb_aluno a     ON a.id_aluno = m.id_aluno
UNION ALL
SELECT DISTINCT 'professor', pr.nm_professor, pr.ds_email
  FROM turmas_bd2 tb
  JOIN tb_professor pr ON pr.id_professor = tb.id_professor
 ORDER BY papel DESC, nome;

-- A diferença em números: professores de Estruturas de Dados (CCO020) e de Banco de Dados I (CCO030) no semestre
-- atual. Os mesmos professores dão as duas disciplinas: UNION ALL conta cada um uma vez por turma, UNION conta cada
-- professor uma vez só.
WITH turmas AS (
    SELECT d.cd_disciplina, t.id_professor
      FROM tb_turma t
      JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
     WHERE d.cd_disciplina IN ('CCO020', 'CCO030')
       AND t.id_periodo_letivo = (SELECT id_periodo_letivo FROM tb_periodo_letivo
                                   ORDER BY aa_periodo DESC, cd_semestre DESC LIMIT 1)
)
SELECT 'UNION ALL (com repetidos)' AS tipo, count(*) AS linhas
  FROM (SELECT id_professor FROM turmas WHERE cd_disciplina = 'CCO020'
        UNION ALL
        SELECT id_professor FROM turmas WHERE cd_disciplina = 'CCO030') x
UNION ALL
SELECT 'UNION (sem repetidos)', count(*)
  FROM (SELECT id_professor FROM turmas WHERE cd_disciplina = 'CCO020'
        UNION
        SELECT id_professor FROM turmas WHERE cd_disciplina = 'CCO030') y;
