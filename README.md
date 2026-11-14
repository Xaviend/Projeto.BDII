# Projeto BD2 - Sistema de Matrícula


Projeto da matéria de Banco de Dados II , prof. Rodrigo Gonçalves.

A ideia é montar o banco de um sistema de matrícula de faculdade no PostgreSQL 16: campus, cursos, currículos, disciplinas com pré-requisito, turmas, horários, salas, alunos, matrículas e histórico.

## Grupo

- Iury Xavier 2412130039 - modelagem física e desempenho
- Eduardo Serra 2412130069 - transações e concorrência
- Arthur 2512130004 - administração

Mais detalhes de quem fez o que no AUTORES.md.

## Pastas

- `modelo/` diagrama feito no draw.io
- `sql/` scripts, na ordem que tem que rodar
- `evidencias/` resultado do EXPLAIN antes e depois dos índices (gerado pelo `indices_v1.sql`)

## Scripts

Rodar nesta ordem, todos no banco `matricula`:

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | `sql/modelo_fisico_v1.sql` | Apaga e cria o schema `projeto_bd2` com as 17 tabelas, domínios, enums e restrições. |
| 2 | `sql/testes_restricoes_v1.sql` | Prova que as restrições funcionam: 14 testes que têm que ser barrados. Roda dentro de `BEGIN ... ROLLBACK`, então não deixa nada no banco. Pode pular. |
| 3 | `sql/carga_v1.sql` | Popula o banco com dados de teste (ver "Carga de dados" abaixo). |
| 4 | `sql/indices_v1.sql` | Cria 4 índices (um parcial) e mede o ganho de cada um com `EXPLAIN (ANALYZE, BUFFERS)` (ver "Índices" abaixo). |

(os scripts das outras frentes vão sendo adicionados a medida em que forem feitos)

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

- O `modelo_fisico_v1.sql` apaga e cria o schema de novo, então dá pra rodar várias vezes sem problema. **Mas isso apaga também os dados:** depois dele, roda o `carga_v1.sql` e o `indices_v1.sql` de novo.
- O `carga_v1.sql` e o `indices_v1.sql` também podem ser rodados várias vezes (o primeiro zera as tabelas antes de popular, o segundo apaga os índices antes de criar).
- O `carga_v1.sql` tem que rodar antes do `indices_v1.sql`.

Antes de fazer consulta tem que colocar:

```sql
SET search_path TO projeto_bd2, public;
```

## Carga de dados (`carga_v1.sql`)

Dados **sintéticos** (nomes, CPFs, e-mails e notas inventados), feitos com `generate_series`, sem `random()`: toda vez que roda dá exatamente os mesmos dados. Não vêm do schema academico do professor.

Quantidade (o Marco 1 pede no mínimo 100 alunos, 6 turmas e 300 matrículas):

| Tabela | Linhas |
|---|---|
| tb_aluno | 2000 |
| tb_turma | 1536 (192 por semestre, 8 semestres de 2023/1 a 2026/2) |
| tb_matricula | ~25 mil |
| tb_historico | ~24,6 mil |

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

## Índices (`indices_v1.sql`)

Para cada índice o script faz: EXPLAIN antes, CREATE INDEX, EXPLAIN depois da mesma consulta.

| # | Índice | Consulta | Por que |
|---|---|---|---|
| 1 | `ix_matricula_turma_ativa` em tb_matricula (id_turma) **WHERE ds_status = 'ativa'** (parcial) | vagas ocupadas de uma turma | só as matrículas ativas ocupam vaga; o índice guarda só elas e fica bem menor que um índice completo |
| 2 | `ix_historico_situacao_media` em tb_historico (ds_situacao, qt_media_final DESC) | top 10 médias dos aprovados | filtro e ordenação no mesmo índice: lê 10 linhas e para, sem ordenar tudo |
| 3 | `ix_matricula_dt` em tb_matricula (dt_matricula) | últimas 20 matrículas | percorre o índice de trás pra frente e para na 20ª |
| 4 | `ix_aluno_nm_pattern` em tb_aluno (nm_aluno varchar_pattern_ops) | aluno pelo começo do nome (`LIKE 'Ana Silva%'`) | índice comum não atende LIKE com collation de idioma; só serve pra prefixo, não pra `%texto%` |

Os planos aparecem na aba **Messages** do pgAdmin e o resumo (tempo e páginas lidas, antes e depois) na aba **Data Output**. As páginas lidas (buffers) quase não mudam de uma execução pra outra; o tempo muda um pouco.

### Como gerar as evidências

1. Roda o `modelo_fisico_v1.sql`, o `carga_v1.sql` e o `indices_v1.sql` nessa ordem.
2. Copia o conteúdo da aba Messages pra `evidencias/explain_indices_v1.txt`.
3. Exporta o resumo da aba Data Output (botão de download) pra `evidencias/resumo_indices_v1.csv`.
4. Commit dos dois arquivos.

Gerar de novo na máquina de cada um, porque o tempo depende do computador.

## Sobre o modelo

O diagrama tá em modelo/modelo_logico.v3.drawio (abre no app.diagrams.net). Tem as 17 tabelas com os tipos, PK, FK e a cardinalidade (mín,máx) de cada relacionamento.

Padrão de nomes :

- tabelas com tb_, tipos enum com tp_, domínios com dm_ (views vw_, funções fn_, triggers trg_, procedures stp_)
- toda PK é id_<tabela> e a FK tem o mesmo nome da PK que ela aponta
- as outras colunas começam com: cd_ código, ds_ descrição, dt_ data, dd_ dia, aa_ ano, hr_ hora, ic_ sim/não, nm_ nome, qt_ valor não monetário, sg_ sigla, pc_ porcentagem, vl_ valor em dinheiro

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

Combinamos assim:

- Não demos commit na main, ela só recebe o que está funcionando
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
