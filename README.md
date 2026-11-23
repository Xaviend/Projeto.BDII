# Projeto BD2 - Sistema de Matrícula


Projeto da matéria de Banco de Dados II, prof. Rodrigo Gonçalves.

A ideia é montar o banco de um sistema de matrícula de faculdade no PostgreSQL 16: campus, cursos, currículos, disciplinas com pré-requisito, turmas, horários, salas, alunos, matrículas e histórico.

## Grupo

- Iury Xavier 2412130039 - modelagem física e desempenho
- Eduardo Serra 2412130069 - transações e concorrência
- Arthur 2512130004 - administração

Mais detalhes de quem fez o que no AUTORES.md.

## Pastas

- `modelo/` modelo conceitual e modelo lógico, feitos no draw.io
- `sql/` scripts, numerados na ordem em que têm que rodar
- `evidencias/` resultado do EXPLAIN antes e depois dos índices (gerado pelo `04_indices_v1.sql`), a saída das duas abas na demonstração de concorrência e as saídas da frente de administração (materialized view, GIN, testes de segurança e backup). Lista completa em "Evidências" no fim deste arquivo
- `docs/` passo a passo do backup e da restauração
- `ferramentas/` os scripts que geraram as evidências numa rodada do zero (ver "Evidências" no fim)

## Scripts

Rodar na ordem do número do arquivo, todos no banco `matricula`:

| Ordem | Arquivo | O que faz |
|---|---|---|
| 01 | `sql/01_modelo_fisico_v1.sql` | Apaga e cria o schema `projeto_bd2` com as 17 tabelas, domínios, enums e restrições. |
| 02 | `sql/02_testes_restricoes_v1.sql` | Prova que as restrições funcionam: 75 testes que têm que ser barrados (CHECK, UNIQUE, NOT NULL, PK, FK simples e composta, EXCLUDE, domínio, enum e coluna gerada), cada um conferindo pelo nome que quem barrou foi a restrição certa, e 4 conferências. A última (bloco 8) lê no catálogo todas as restrições CHECK, UNIQUE, FK e EXCLUDE do schema (inclusive as dos domínios) e dá FALHOU se alguma ficou sem teste. Na aba Messages: 75 "OK barrado", 4 "OK conferido" e nenhum "FALHOU". Roda dentro de `BEGIN ... ROLLBACK`, então não deixa nada no banco, e dá o mesmo resultado antes ou depois da carga. |
| 03 | `sql/03_carga_v1.sql` | Popula o banco com dados de teste (ver "Carga de dados" abaixo). |
| 04 | `sql/04_indices_v1.sql` | Cria 4 índices (um parcial) e mede o ganho de cada um com `EXPLAIN (ANALYZE, BUFFERS)` (ver "Índices" abaixo). |
| 05a | `sql/05a_concorrencia_preparacao_v1.sql` | Confere o banco e guarda a turma e os alunos da demonstração da "última vaga". Roda nas DUAS abas. Sem ele os scripts 05b, 05c e 05d dão erro. |
| 05b | `sql/05b_concorrencia_erro_v1.sql` | Reproduz o erro: dois alunos pegam a última vaga e a turma fica com 36 matrículas para 35 vagas. |
| 05c | `sql/05c_concorrencia_solucao1_for_update_v1.sql` | Solução 1: trava a linha da turma com `SELECT ... FOR UPDATE`. |
| 05d | `sql/05d_concorrencia_solucao2_serializable_v1.sql` | Solução 2: isolamento `SERIALIZABLE`, o banco derruba uma das transações (erro 40001) e ela é repetida. |
| 05e | `sql/05e_concorrencia_limpeza_v1.sql` | Apaga as matrículas dos testes e volta a turma pra 1 vaga livre. Roda antes de cada teste de concorrência (ver "Transações e concorrência" abaixo). |
| 06 | `sql/06_consultas_v1.sql` | As 10 consultas comentadas do Marco 1 (junção externa com agregação, duas recursivas, ranking com percentil, LAG e mais 5). Só lê. |
| 07 | `sql/07_administracao_views_v1.sql` | Cria as views `vw_oferta`, `vw_vagas` e `vw_historico` e a materialized view `mv_indicadores`, e mede o ganho da materialized view com EXPLAIN. |
| 08 | `sql/08_administracao_auditoria_v1.sql` | Gatilho que grava em `tb_log_matricula` o antes e o depois (JSONB) de toda mudança de matrícula e de nota, a trava que recusa INSERT direto no log, e o índice GIN no JSONB (bônus) com EXPLAIN antes e depois. |
| 09 | `sql/09_administracao_seguranca_v1.sql` | Papéis aluno, secretaria e coordenacao, REVOKE de tudo, GRANT só do necessário e RLS (o aluno só vê o próprio histórico). **Roda depois de todos os que criam objeto**: fecha as permissões de tudo que já existe. |
| 10 | `sql/10_administracao_seguranca_testes_v1.sql` | 29 testes de segurança (o que pode funciona, o que não pode é barrado, e a lista exata de permissões, papéis e policies). `BEGIN ... ROLLBACK`, não deixa nada no banco. A última linha da aba Messages dá o veredito: "RESULTADO: todos os testes deram OK"; se algum teste falhar, o script termina com ERRO e diz quantos falharam. |
| 11 | `sql/11_administracao_backup_conferencia_v1.sql` | Impressão digital do banco (linhas e md5 de cada tabela e da estrutura) para provar que a restauração do backup ficou igual. Só lê. |

A demonstração de concorrência (05a a 05e) também funciona depois do 11, com o banco completo: foi testada assim, e as matrículas do teste aparecem no log de auditoria do 08.

O backup e a restauração são comandos no terminal, não um script do pgAdmin: o passo a passo está em [`docs/backup_restauracao.md`](docs/backup_restauracao.md).

## Como rodar

### 1. Subir o banco

Precisa do Docker Desktop instalado e aberto (a baleia tem que estar verde).

Baixa o ambiente_aluno_PG16.zip do Sala de Aula, descompacta numa pasta e abre o terminal dentro dela. Aí roda:

```
docker compose up -d
```

Pra ver se subiu:

```
docker compose ps
```

Tem que aparecer o bd2_postgres e o bd2_pgadmin com status Up.

Obs: a pasta do ambiente do professor é uma coisa e a pasta do repositório é outra, não precisa colocar uma dentro da outra.

### 2. Conectar no pgAdmin

Botão direito em Servers > Register > Server e preenche assim:

- Name: BD2_Docker
- Host: postgres se estiver usando o pgAdmin pelo navegador (localhost:8080) ou localhost se for o pgAdmin instalado
- Port: 5432
- Database: matricula
- Usuário: bd2
- Senha: bd2

A gente usou o pgAdmin instalado porque dá pra abrir os arquivos do repositório direto pelo Open File.

### 3. Rodar os scripts

Clica no banco matricula, abre o Tools > Query Tool, abre o arquivo pela pastinha e aperta F5. Tem que rodar na ordem da tabela de scripts lá em cima.

Tudo do projeto fica no schema projeto_bd2 pra não misturar com o schema academico que já vem no banco do professor.

- O `01_modelo_fisico_v1.sql` apaga e cria o schema de novo, então dá pra rodar várias vezes sem problema. **Mas isso apaga tudo que estava no schema:** dados, índices, views, gatilhos, permissões e policies. Depois dele, roda de novo todos os outros na ordem da tabela (do 03 ao 11; o 02 é opcional).
- O `03_carga_v1.sql` e o `04_indices_v1.sql` também podem ser rodados várias vezes (o primeiro zera as tabelas antes de popular, o segundo apaga os índices antes de criar). Só que depois do `08_administracao_auditoria_v1.sql` os gatilhos de auditoria já existem: rodar o 03 de novo faz eles registrarem cada linha da carga, e o log fica com 49.928 linhas (medido), não as 25.351 das evidências. Para voltar ao estado das evidências, roda de novo do 01 ao 11.
- O `03_carga_v1.sql` tem que rodar antes do `04_indices_v1.sql`.
- Os scripts de concorrência são diferentes: não é F5 no arquivo todo, é passo a passo em duas abas (ver "Transações e concorrência" abaixo).
- Os scripts de administração (07 a 11) também podem rodar várias vezes. Se rodar o `07_administracao_views_v1.sql` de novo, roda o `09_administracao_seguranca_v1.sql` depois: a materialized view é recriada e perde as permissões.
- No F5 do `07` e do `08` a aba Messages mostra "WARNING: there is no transaction in progress". É esperado: o `COMMIT` antes do bloco de teste fecha a transação que o pgAdmin abre para o arquivo inteiro (está explicado nos dois scripts).
- Versão: testado no PostgreSQL 16 (imagem `postgres:16` do ambiente da disciplina) e no 17 (o enunciado cita o 17). Todos os scripts rodam com F5 nas duas versões, sem erro (`evidencias/rodada_f5_v1.txt`).
- Os papéis (aluno, secretaria, coordenacao) são do servidor, não do schema: continuam existindo depois do `01_modelo_fisico_v1.sql`. As permissões e as policies somem junto com as tabelas e voltam rodando o `09_administracao_seguranca_v1.sql`.

Antes de fazer consulta tem que colocar:

```sql
SET search_path TO projeto_bd2, public;
```

## Carga de dados (`03_carga_v1.sql`)

Dados **sintéticos** (nomes, CPFs, e-mails e notas inventados), feitos com `generate_series`, sem `random()`: toda vez que roda dá exatamente os mesmos dados. Não vêm do schema academico do professor.

Quantidade (o Marco 1 pede no mínimo 100 alunos, 6 turmas e 300 matrículas):

| Tabela | Linhas |
|---|---|
| tb_aluno | 2000 |
| tb_turma | 1536 (192 por semestre, 8 semestres de 2023/1 a 2026/2) |
| tb_matricula | 24.964 |
| tb_historico | 24.577 |

Ficou bem acima do mínimo de propósito: com poucas linhas o PostgreSQL lê a tabela inteira e o índice não mostra ganho no EXPLAIN.

O que os dados têm:

- 3 cursos (Ciência da Computação, Sistemas de Informação, ADS) e 4 currículos (CCO tem a grade 2022, inativa, e a 2026)
- 24 disciplinas com 25 pré-requisitos, formando cadeias de até 6 disciplinas (serve pras consultas recursivas)
- 2 campus: Asa Sul tem os cursos e Goiânia Centro fica sem nenhum, de propósito, pra junção externa mostrar um campus com 0
- cada aluno cursa as disciplinas do semestre da grade em que está; ninguém cursa disciplina sem ter passado no pré-requisito e ninguém tem duas aulas no mesmo horário
- só se reprova em disciplina que nenhuma outra exige (assim a regra do pré-requisito nunca é quebrada)
- semestres passados: matrícula `concluida` com histórico (aprovado, reprovado_nota ou reprovado_falta). 2026/2: matrícula `ativa` com histórico `cursando`. `trancada` e `cancelada` ficam sem histórico (o (0,1) do modelo)
- alunos de 1 em cada 23 evadiram (`ic_ativo` falso) e têm as matrículas do semestre atual canceladas
- **a turma de Banco de Dados II (CCO072) de 2026/2, seção A, tem exatamente 1 vaga livre**: é a "última vaga" pra frente de transações reproduzir a anomalia de concorrência

No fim do script tem uma conferência que mostra as contagens e a vaga livre dessa turma.

## Índices (`04_indices_v1.sql`)

Para cada índice o script faz: EXPLAIN antes, CREATE INDEX, EXPLAIN depois da mesma consulta.

| # | Índice | Consulta | Por que |
|---|---|---|---|
| 1 | `ix_matricula_turma_ativa` em tb_matricula (id_turma) **WHERE ds_status = 'ativa'** (parcial) | vagas ocupadas de uma turma | só as matrículas ativas ocupam vaga; o índice guarda só elas e fica bem menor que um índice completo |
| 2 | `ix_historico_situacao_media` em tb_historico (ds_situacao, qt_media_final DESC) | top 10 médias dos aprovados | filtro e ordenação no mesmo índice: lê 10 linhas e para, sem ordenar tudo |
| 3 | `ix_matricula_dt` em tb_matricula (dt_matricula) | últimas 20 matrículas | percorre o índice de trás pra frente e para na 20ª |
| 4 | `ix_aluno_nm_pattern` em tb_aluno (nm_aluno varchar_pattern_ops) | aluno pelo começo do nome (`LIKE 'Ana Silva%'`) | índice comum não atende LIKE com collation de idioma (o script cria um índice comum de controle e o plano continua Seq Scan com a collation `en_US.utf8` do banco); só serve pra prefixo, não pra `%texto%` |

Os planos aparecem na aba **Messages** do pgAdmin e o resumo (tempo e páginas lidas, antes e depois) na aba **Data Output**. As páginas lidas (buffers) quase não mudam de uma execução pra outra; o tempo muda um pouco.

### Ganho medido

Banco criado do zero (01 a 04), PostgreSQL 16. Cada consulta roda duas vezes e só a segunda conta (a primeira esquenta o cache). Página = bloco de 8 kB lido.

| # | Plano antes | Plano depois | Tempo | Páginas lidas |
|---|---|---|---|---|
| 1 | Index Scan no índice único (id_aluno, id_turma): como id_turma é a 2ª coluna, ele percorre o índice inteiro | Bitmap Index Scan no `ix_matricula_turma_ativa`, direto nas 34 matrículas ativas da turma | 0,154 ms → 0,027 ms (5,7 vezes) | 102 → 31 |
| 2 | Seq Scan no histórico inteiro (24.577 linhas, 19.174 aprovadas) e ordenação | Index Scan no `ix_historico_situacao_media`, para na 10ª linha | 2,370 ms → 0,012 ms (197,5 vezes) | 197 → 12 |
| 3 | Seq Scan nas 24.964 matrículas e ordenação | Index Scan Backward no `ix_matricula_dt`, para na 20ª linha | 2,194 ms → 0,012 ms (182,8 vezes) | 184 → 22 |
| 4 | Seq Scan nos 2000 alunos (com o índice comum de controle também) | Index Scan no `ix_aluno_nm_pattern` | 0,070 ms → 0,010 ms (7,0 vezes) | 31 → 3 |

O índice parcial (só matrículas ativas) ocupa 56 kB. O mesmo índice com todas as matrículas ocuparia 208 kB.

As saídas completas estão em `evidencias/explain_indices_v1.txt` (aba Messages: os planos de antes e de depois) e em `evidencias/resumo_indices_v1.csv` (aba Data Output: o resumo).

### Como gerar as evidências de novo

1. Roda o `01_modelo_fisico_v1.sql`, o `03_carga_v1.sql` e o `04_indices_v1.sql` nessa ordem.
2. Copia o conteúdo da aba Messages pra `evidencias/explain_indices_v1.txt`.
3. Exporta o resumo da aba Data Output (botão de download) pra `evidencias/resumo_indices_v1.csv`.

O tempo muda de um computador pro outro. As páginas lidas e o tipo de plano (Seq Scan, Index Scan) costumam ficar iguais, porque a carga gera sempre os mesmos dados.

## Transações e concorrência

O problema: dois alunos tentam pegar a última vaga da turma CCO072 2026/2 A ao mesmo tempo. No READ COMMITTED (o padrão do PostgreSQL) os dois contam as vagas antes de algum dar COMMIT, os dois veem 1 livre e os dois se matriculam. A turma estoura.

Alunos da demonstração: 26000001 (ABA 1, do 1º semestre) e 26000002 (ABA 2, do 2º semestre). Nenhum dos dois está na turma; eles só entram nela durante o teste e a limpeza apaga depois.

### Como rodar

1. Abre DUAS abas de Query Tool no banco matricula (ABA 1 e ABA 2).
2. Roda o `05e_concorrencia_limpeza_v1.sql` numa aba (F5). Tem que dar `vagas_livres = 1`.
3. Roda o `05a_concorrencia_preparacao_v1.sql` nas DUAS abas (F5). Os parâmetros valem só pra aba onde rodou.
4. Abre o script do teste e roda **um passo de cada vez, só na aba indicada**: seleciona o trecho do passo e aperta F5 (sem selecionar ele roda o arquivo todo e estraga o teste).
5. Antes do próximo teste, volta pro passo 2.

Se a limpeza der erro dizendo que tem transação aberta, roda `ROLLBACK;` nas outras abas e tenta de novo. Matrícula que ainda não teve COMMIT não aparece pro DELETE, então ela ficaria no banco e o próximo teste começaria com a turma cheia.

### O que tem que acontecer

A turma começa com 35 vagas e 34 ocupadas (1 livre).

| Script | ABA 1 | ABA 2 | Resultado final |
|---|---|---|---|
| `05b_concorrencia_erro_v1.sql` | matricula | também matricula | 36 ocupadas, `vagas_livres = -1` (o erro) |
| `05c_concorrencia_solucao1_for_update_v1.sql` | trava a turma e matricula | fica travada esperando, depois `INSERT 0 0` | 35 ocupadas, `vagas_livres = 0` |
| `05d_concorrencia_solucao2_serializable_v1.sql` | matricula | erro 40001, repete (retry) e dá `INSERT 0 0` | 35 ocupadas, `vagas_livres = 0` |

Nas duas soluções as duas abas rodam o mesmo INSERT, que só insere se ainda tiver vaga. Quem decide é o banco, não a pessoa olhando o resultado.

Só a conferência dentro do INSERT não basta. Sem o FOR UPDATE e sem o SERIALIZABLE, as duas abas contam 34 ocupadas ao mesmo tempo, as duas inserem e a turma fica com 36 (medido: X4).

A saída das duas abas, passo a passo, está em `evidencias/concorrencia_duas_abas_v1.txt`. Ela foi gerada com duas sessões abertas ao mesmo tempo (o mesmo que as duas abas do Query Tool), mandando cada passo só para a aba que o script indica.

### Comparação entre as duas soluções

O que está marcado como "medido" vem do arquivo de evidência acima (as medições X1 a X5 estão no fim dele). O resto vem do manual do PostgreSQL 16 (seções 13.2.3, 13.3.2 e 13.3.4).

| | FOR UPDATE (pessimista) | SERIALIZABLE (otimista) |
|---|---|---|
| Como protege | Tranca a linha da turma antes de contar as vagas. Quem chega depois espera. | Ninguém tranca nada. O banco observa o que cada transação leu e escreveu e derruba uma quando o resultado não bate com uma execução uma depois da outra. |
| Custo | Uma trava na linha da turma, marcada na própria linha: não ocupa memória, mas o manual avisa que isso gera escrita em disco. | O banco guarda travas de leitura (SIReadLock) na memória. Medido: a contagem de vagas da turma A pegou 4 travas (X1). E o trabalho da transação derrubada é feito de novo. |
| Contenção | Só quem disputa a mesma turma espera. Medido: com a mesma turma a ABA 2 ficou parada até o COMMIT da ABA 1 (05c, passo 3). Com turmas diferentes ninguém esperou (X3). | Ninguém espera (o manual diz que essas travas não bloqueiam). Mas o banco pode derrubar transação que não tinha conflito de verdade. Medido: ABA 1 na turma A e ABA 2 na turma B, e mesmo assim a ABA 2 levou o erro 40001 (X2). |
| Retentativa | Não precisa. Quem perdeu a vaga recebe `INSERT 0 0` e a aplicação mostra "turma cheia". | Obrigatória. A aplicação precisa pegar o erro 40001 e repetir a transação inteira (05d, passo 5). |
| Risco | Deadlock se uma transação trancar duas turmas numa ordem e outra na ordem contrária. O banco derruba uma delas. Para evitar: trancar sempre em ordem de `id_turma`. | Mais erro 40001 do que o necessário quando a transação lê muitas linhas da mesma tabela (ver abaixo). |
| Condição | Todo lugar que matricula tem que fazer o FOR UPDATE antes de contar as vagas. | Todas as transações de matrícula têm que rodar em SERIALIZABLE. |

Por que o SERIALIZABLE derrubou matrícula de turma diferente (X2): a contagem de vagas lê as 34 matrículas ativas da turma, e o PostgreSQL guarda no máximo 32 travas de leitura por tabela em cada transação (`max_pred_locks_per_transaction` = 64, dividido por 2 em `max_pred_locks_per_relation`). Passou disso, ele troca as 34 por uma trava na tabela `tb_matricula` inteira (X1 mostra essa trava). Aí qualquer matrícula nova, em qualquer turma, conta como conflito. Numa turma com 25 matrículas ativas isso não aconteceu (X5): ficaram 25 travas de linha em `tb_matricula`, 1 de linha na turma e 2 de página nos índices, e nenhuma trava na tabela inteira.

Qual usar na matrícula: o FOR UPDATE. A disputa é sempre pela mesma linha (a turma), a fila só se forma entre quem quer a mesma turma, e a aplicação não precisa de laço de repetição. O SERIALIZABLE vale mais quando há muitas regras e é difícil prever quem conflita com quem. Nesse caso o manual recomenda usar SERIALIZABLE em tudo e tratar o 40001 em um lugar só.

## Administração e operação

### Views e materialized view (`07_administracao_views_v1.sql`)

| Objeto | O que mostra | Como roda |
|---|---|---|
| `vw_oferta` | turmas de cada semestre com disciplina, professor, turno e horários | `security_invoker`: com o papel de quem consulta |
| `vw_vagas` | vagas, ocupadas, livres e situação (lotada, últimas vagas, com vagas) de cada turma | do dono: conta as matrículas de todos, mas não mostra de quem são (o aluno vê as vagas sem ver os colegas) |
| `vw_historico` | histórico do aluno com notas, frequência e situação | `security_invoker`: o RLS vale dentro da view, cada aluno vê só o dele |
| `mv_indicadores` | aprovação, reprovação, média e frequência por curso e semestre | materialized view: o resultado fica gravado |

Política de atualização da `mv_indicadores`: `REFRESH MATERIALIZED VIEW CONCURRENTLY` depois de cada lançamento de notas e uma vez por noite, sempre pela função `fn_atualizar_indicadores()` (a coordenação executa sem ser dona da view). O agendamento da noite fica fora do banco: a imagem `postgres:16` do ambiente não traz o `pg_cron` (conferido em `pg_available_extensions`), então em produção seria um job do servidor rodando `SELECT projeto_bd2.fn_atualizar_indicadores();`. No projeto o refresh é chamado à mão (bloco 5 do 07). O `CONCURRENTLY` não trava a leitura durante o refresh e precisa do índice único `uq_mv_indicadores`. Não tem refresh por gatilho: nota muda o tempo todo durante o semestre e indicador de gestão não precisa ser do segundo. A coluna `dt_atualizacao` mostra de quando são os números. Ganho medido: 17,0 ms e 426 páginas calculando na hora, 0,008 ms e 1 página lendo da materialized view.

### Segurança (`09_administracao_seguranca_v1.sql`)

Negado por padrão: REVOKE de tudo para todos e GRANT só do que cada papel precisa.

| | aluno | secretaria | coordenacao |
|---|---|---|---|
| views de oferta e vagas | lê | lê | lê |
| histórico | só o próprio (RLS) | tudo | tudo |
| `mv_indicadores` | - | lê | lê e atualiza |
| tb_aluno | só o próprio (RLS) | lê, inclui, altera | lê sem CPF, e-mail e nascimento |
| tb_matricula | só as próprias (RLS) | lê, inclui, altera só o status | lê |
| tb_log_matricula | - | lê; inclui só pelo gatilho, sem escolher usuário e data | lê |
| funções | `fn_matricula_do_usuario` (usada pelo RLS) | - | `fn_atualizar_indicadores` |
| DELETE | - | - | - |

Cada aluno tem um papel `aluno_<matrícula>` (para a demonstração: `aluno_26000001` e `aluno_26000012`). A policy compara a matrícula da linha com o usuário conectado. O `bd2` é superusuário e passa por cima do RLS, por isso os testes trocam de papel com `SET ROLE`.

Rodar o script de novo desfaz mudança feita à mão: os papéis voltam sem LOGIN, SUPERUSER e BYPASSRLS e saem de grupo errado, as permissões saem todas antes dos GRANT e todas as policies das três tabelas são apagadas antes de criar as nove da matriz.

Os 29 testes, os 24 mutantes que provam que eles pegam erro e a saída estão em `evidencias/testes_seguranca_v1.txt`. Os testes 27 a 29 comparam o banco com a lista exata do permitido: permissão de tabela e de coluna, sequence, função e schema; atributos e grupos dos papéis; e as policies.

### Auditoria e bônus JSONB com GIN (`08_administracao_auditoria_v1.sql`)

Os gatilhos `trg_log_matricula` e `trg_log_historico` gravam cada INSERT, UPDATE e DELETE de `tb_matricula` e de `tb_historico` (as notas) em `tb_log_matricula`, com a tabela, a linha antes e depois em JSONB, o papel que fez (`CURRENT_USER`, em `nm_usuario`) e o usuário que conectou (`session_user`, em `usuario_sessao` dentro do JSON). O gatilho `trg_log_so_pelo_gatilho` recusa INSERT feito direto no log: a secretaria precisa de INSERT no log para o gatilho funcionar, e sem essa trava poderia inventar uma linha.

O índice GIN `ix_log_matricula_detalhe` (`jsonb_path_ops`) atende a busca "toda a movimentação de um aluno" (`ds_detalhe @> '{"depois": {"id_aluno": 12}}'`): de 16,9 ms e 896 páginas (leitura da tabela inteira) para 0,063 ms e 5 páginas.

Fica fora do log: mudança no cadastro do aluno (`tb_aluno`), porque o log é por matrícula. A secretaria é o único papel que altera `tb_aluno`.

O `08_administracao_auditoria_v1.sql` tem que rodar como superusuário (o `bd2` do ambiente do professor é): a carga inicial do log grava direto na tabela, e a trava só deixa superusuário fazer isso.

### Backup e restauração

`pg_dump -n projeto_bd2 -Fc` e `pg_restore`, rodando dentro do container. Passo a passo, casos de restauração e perguntas em [`docs/backup_restauracao.md`](docs/backup_restauracao.md). Ensaio com a impressão digital igual antes e depois em `evidencias/backup_restauracao_v1.txt`.

## Evidências

| Arquivo | O que tem | Gerado por |
|---|---|---|
| `evidencias/testes_restricoes_v1.txt` | os 75 testes de restrição antes e depois da carga e os 72 mutantes (banco com um defeito só: uma restrição tirada, o NOT NULL da turma tirado ou uma restrição nova sem teste) com o FALHOU que o 02 deu em cada um | `02` |
| `evidencias/explain_indices_v1.txt` | EXPLAIN (ANALYZE, BUFFERS) de cada consulta antes e depois de cada índice | `04_indices_v1.sql`, aba Messages |
| `evidencias/resumo_indices_v1.csv` | tempo e páginas lidas antes e depois, e quantas vezes ficou mais rápido | `04_indices_v1.sql`, aba Data Output |
| `evidencias/concorrencia_duas_abas_v1.txt` | as duas abas passo a passo no erro e nas duas soluções, as medições X1 a X5 da comparação e a mesma demonstração de novo com o banco completo (depois do 11) | `05a` a `05e`, em duas sessões ao mesmo tempo |
| `evidencias/consultas_v1.txt` | o resultado das 10 consultas | `06` |
| `evidencias/cardinalidade_minima_v1.txt` | quantos "pais" ficam sem filho na carga, a base da tabela de cardinalidade acima | `ferramentas/cardinalidade_minima.sql` |
| `evidencias/explain_administracao_v1.txt` | ganho da materialized view e do índice GIN | `07` e `08` |
| `evidencias/testes_seguranca_v1.txt` | os 29 testes de segurança, os 24 mutantes e o comando de cada mutante | `10` |
| `evidencias/backup_restauracao_v1.txt` | impressão digital igual antes e depois da restauração | `11` e os comandos de `docs/backup_restauracao.md` |
| `evidencias/rodada_f5_v1.txt` | cada script rodado como o F5 do pgAdmin (o arquivo inteiro de uma vez), no PostgreSQL 16 e no 17, e o que ficou gravado depois de cada um | `ferramentas/f5_emulacao.sh` |

Todos os arquivos de evidência foram gerados na mesma rodada, com o banco criado do zero pelos scripts 01 a 11 na ordem da tabela, no PostgreSQL 16 (imagem `postgres:16`, a mesma do ambiente da disciplina). A data e a versão estão no cabeçalho de cada arquivo. A rodada usou o `psql`, que mostra o mesmo conteúdo das abas Messages e Data Output do pgAdmin.

Para gerar tudo de novo (Docker aberto, Git Bash na pasta do repositório): `bash ferramentas/rodada_completa.sh`. Ele cria um container de teste próprio (`bd2_teste_pg16`, sem porta publicada), não mexe no `bd2_postgres` da aula e reescreve os arquivos de `evidencias/`.

## Sobre o modelo

Os dois diagramas abrem no app.diagrams.net e seguem o modelo da Aula 04: fundo branco, cabeçalho do IESB, linhas sem curva (retas no conceitual, em ângulo reto no lógico) e o par (mín,máx) escrito nas duas pontas de cada relacionamento.

- `modelo/modelo_conceitual.drawio`: o modelo conceitual (DER) na notação de Chen. 12 entidades (retângulo), mais a entidade associativa MATRÍCULA (losango dentro do retângulo) entre ALUNO e TURMA, 15 relacionamentos (losango com um verbo) e os atributos (elipse; o identificador sublinhado e os calculados tracejados). O rodapé explica como ler a cardinalidade, onde a mínima é 0 e por quê, e como o conceitual vira o lógico: cada entidade vira tabela, o 1:N vira FK no lado N, o 1:1 (matrícula gera histórico) vira FK com UNIQUE e os quatro N:N viram as tabelas associativas tb_matricula, tb_curriculo_disciplina, tb_pre_requisito e tb_turma_horario.
- `modelo/modelo_logico.drawio`: o modelo lógico com as 17 tabelas (as 12 entidades, as 4 associativas e o log de auditoria), com colunas, tipos, PK, FK, únicos e colunas geradas. Cada linha liga a tabela da FK à tabela da PK, com o par (mín,máx) nas duas pontas. O rodapé lista os únicos de várias colunas e as regras que não viram linha: as duas FKs compostas, o EXCLUDE de horário, o log sem FK e o feriado nacional (campus nulo).

### Como ler a cardinalidade

O par fica junto da entidade (ou tabela) que começa a frase, como na Aula 04. Exemplo: `CAMPUS (1,N) ---- possui ---- (1,1) SALA` se lê "um campus possui de 1 a N salas" e "uma sala fica em exatamente 1 campus". Os comentários das FKs no `01_modelo_fisico_v1.sql` usam o mesmo padrão.

- Do lado da FK, a mínima vira restrição: (1,1) = FK `NOT NULL`; (0,1) = FK que aceita nulo (só em tb_feriado, onde nulo é feriado nacional). O `02_testes_restricoes_v1.sql` prova: matrícula sem turma é barrada pelo NOT NULL (bloco 7f), o segundo histórico da mesma matrícula é barrado pelo UNIQUE (bloco 7i) e cada FK do modelo tem um teste com o pai inexistente.
- Do lado da PK, a mínima é regra do negócio: o DDL não obriga um pai a ter filho (como no exemplo da aula, ALUNO (1,N) cursa TURMA). Por isso a mínima 0 só aparece onde a carga tem um caso real de pai sem filho. Em todos os outros pares a mínima é 1, e a contagem de pai sem filho no banco criado do zero deu 0 (as 21 contagens estão em `evidencias/cardinalidade_minima_v1.txt`).

| Relacionamento | Onde a mínima é 0 | Caso real na carga |
|---|---|---|
| FERIADO vale para CAMPUS | FERIADO (0,1) e CAMPUS (0,N) | 6 feriados nacionais, sem campus; o campus Goiânia Centro não tem feriado local |
| CAMPUS oferece CURSO | CAMPUS (0,N) | Goiânia Centro não tem curso (1 dos 2 campus) |
| DISCIPLINA exige DISCIPLINA | (0,N) nas duas pontas | 4 das 24 disciplinas não têm pré-requisito; 7 não são pré-requisito de nenhuma |
| TURMA ocupa SALA (horário) | SALA (0,N) | 4 das 12 salas não têm horário |
| ALUNO matricula-se em TURMA | TURMA (0,N) | 512 das 1.536 turmas não têm matrícula |
| MATRÍCULA gera HISTÓRICO | MATRÍCULA (0,1) | 387 das 24.964 matrículas não têm histórico (as 169 trancadas e as 218 canceladas) |

### Regras que ficaram fora do banco (decisão do grupo)

- Professor em duas turmas no mesmo horário: o EXCLUDE de `tb_turma_horario` barra só a sala; o professor fica para a aplicação da secretaria.
- Períodos letivos que se sobrepõem: o banco confere só que o fim vem depois do início e que o ano bate com as datas.
- Dígito verificador do CPF: o CHECK confere 11 dígitos e barra os 11 iguais; o cálculo do dígito fica na aplicação.
- Pré-requisito na hora da matrícula: o banco guarda quem exige quem, mas não barra a matrícula de quem não passou; a carga respeita a regra e a aplicação confere.
- Limite de vagas da turma: um CHECK não enxerga as outras linhas, então quem garante é a transação (05c e 05d).

Padrão de nomes:

- tabelas com tb_, tipos enum com tp_, domínios com dm_ (views vw_, materialized views mv_, funções fn_, triggers trg_, procedures stp_, policies de RLS pol_)
- toda PK é id_<tabela> e a FK tem o mesmo nome da PK que ela aponta
- as outras colunas começam com: cd_ código, ds_ descrição, dt_ data, dd_ dia, aa_ ano, hr_ hora, ic_ sim/não, nm_ nome, qt_ valor não monetário, sg_ sigla, pc_ porcentagem, vl_ valor em dinheiro
- arquivos .sql: o número da ordem de execução na frente, minúsculo, com _ e terminando em _v1 (ex: `03_carga_v1.sql`); os da mesma frente têm o mesmo nome depois do número (ex: `05a_concorrencia_...` a `05e_concorrencia_...`)

Tipos que a gente usou:

- int pras chaves e smallint pra números pequenos (vagas, capacidade, ano)
- char quando o tamanho é sempre igual (cpf com 11, uf com 2)
- varchar pra nome, código, email
- numeric(4,2) pras notas e numeric(5,2) pra frequência, através dos domínios dm_nota (0 a 10) e dm_percentual (0 a 100)
- date, time e timestamp pra datas e horários
- enum (tp_) pras coisas que só têm algumas opções (turno, status, situação...)

Algumas restrições que vale comentar:

- qt_ch_total da disciplina e qt_media_final do histórico são colunas geradas, o próprio banco calcula
- o aluno tem uma FK composta (id_curriculo, id_curso) pra garantir que o currículo dele é do curso dele
- a tb_turma_horario tem um EXCLUDE que não deixa duas turmas na mesma sala no mesmo horário (usando hr_inicio e hr_fim)
- uma disciplina não pode ser pré-requisito dela mesma
- cada matrícula tem no máximo um histórico (UNIQUE no id_matricula)
- o tb_log_matricula não tem FK de propósito, pra o log continuar existindo se apagarem a matrícula

## Como a gente organizou o Git

Como ficou de verdade (dá para conferir com `git log` e `git shortlog -sn`): o Iury e o Eduardo trabalharam nas branches `iury/modelagem_fisica` e `eduardo/transações_e_concorência` e também subiram alguns commits direto na main (os modelos do Iury e a concorrência do Eduardo). Os commits das branches entraram na main com merge, sem squash, então cada commit aparece com o autor. O Arthur trabalhou nas branches `arthur/...`, juntou as frentes na main e fez as revisões finais. Os Pull Requests foram abertos e aceitos pelo Arthur, sem revisão registrada no GitHub; a revisão das outras frentes foi feita rodando os scripts do zero (ver `AUTORES.md`).

O que tínhamos combinado:

- não dar commit direto na main, ela só recebe o que está funcionando
- cada um tem sua branch com o nome e a parte que tá fazendo, ex: nome1/modelagem-fisica
- commit pequeno, um pra cada parte que funcionou, nada de subir tudo de uma vez
- quando uma etapa fica pronta abre um Pull Request pra main e alguém do grupo revisa antes de aceitar
- no merge usar "Create a merge commit" e não o Squash, porque o squash junta todos os commits num só e perde o histórico
- cada um mexe nos seus arquivos pra não dar conflito

A gente usa o GitHub Desktop. O dia a dia fica mais ou menos assim:

1. Fetch origin e depois Branch > Update from main (pra pegar o que os outros já subiram)
2. Faz as alterações e testa no pgAdmin
3. Escreve a mensagem, Commit e Push origin
4. Quando terminar uma etapa: Branch > Create pull request, alguém revisa e faz o merge

Pra criar a branch na primeira vez: Current branch > New branch > coloca o nome > Publish branch.

As mensagens de commit a gente tá tentando deixar nesse padrão:

```
ddl: cria tb_cidade e tb_campus
indice: cria índice parcial nas matrículas ativas
transacao: reproduz o erro da última vaga
docs: atualiza readme
```

Se alguém preferir terminal:

```
git switch -c nome/frente
git pull origin main
git add .
git commit -m "mensagem"
git push
```
