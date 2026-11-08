# Projeto BD2 - Sistema de Matrícula


Projeto da matéria de Banco de Dados II , prof. Rodrigo Gonçalves.

A ideia é montar o banco de um sistema de matrícula de faculdade no PostgreSQL 16: campus, cursos, currículos, disciplinas com pré-requisito, turmas, horários, salas, alunos, matrículas e histórico.

Grupo
Iury Xavier 2412130039 - modelagem física e desempenho 
Eduardo Serra 2412130069 - transações e concorrência 
Arthur 2512130004 - administração 

Mais detalhes de quem fez o que no AUTORES.md.

Pastas
modelo /       diagrama feito no draw.io
sql/          scripts, numerados na ordem que tem que rodar
evidencias/   prints/resultados do EXPLAIN antes e depois dos índices

Scripts:

(codigos vão sendo adicionados a medida em que forem feitos).
Como rodar
1. Subir o banco

Precisa do Docker Desktop instalado e aberto (a baleia tem que estar verde).

Baixa o ambiente_aluno_PG16.zip do Sala de Aula, descompacta numa pasta e abre o terminal dentro dela. Aí roda:

docker compose up -d

Pra ver se subiu:

docker compose ps

Tem que aparecer o bd2_postgres e o bd2_pgadmin com status Up.

Obs: a pasta do ambiente do professor é uma coisa e a pasta do repositório é outra, não precisa colocar uma dentro da outra.

2. Conectar no pgAdmin

Botão direito em Servers > Register > Server e preenche assim:

Name: BD2_Docker
Host: postgres se estiver usando o pgAdmin pelo navegador (localhost:8080) ou localhost se for o pgAdmin instalado
Port: 5432
Database: matricula
Usuário: bd2
Senha: bd2

A gente usou o pgAdmin instalado porque dá pra abrir os arquivos do repositório direto pelo Open File.

3. Rodar os scripts

Clica no banco matricula, abre o Tools > Query Tool, abre o arquivo pela pastinha e aperta F5. Tem que rodar na ordem dos números.

Tudo do projeto fica no schema projeto_bd2 pra não misturar com o schema academico que já vem no banco do professor. O script 01 apaga e cria o schema de novo, então dá pra rodar várias vezes sem problema.

Antes de fazer consulta tem que colocar:

sql
SET search_path TO projeto_bd2, public;
Sobre o modelo

O diagrama tá em modelo/Modelo_Logico_Matricula.drawio (abre no app.diagrams.net). Tem as 17 tabelas com os tipos, PK, FK e a cardinalidade (mín,máx) de cada relacionamento.

Padrão de nomes :

tabelas com tb_, tipos enum com tp_, domínios com dm_ (views vw_, funções fn_, triggers trg_, procedures stp_)
toda PK é id_<tabela> e a FK tem o mesmo nome da PK que ela aponta
as outras colunas começam com: cd_ código, ds_ descrição, dt_ data, dd_ dia, aa_ ano, hr_ hora, ic_ sim/não, nm_ nome, qt_ valor não monetário, sg_ sigla, pc_ porcentagem, vl_ valor em dinheiro

Tipos que a gente usou:

int pras chaves e smallint pra números pequenos (vagas, capacidade, ano)
char quando o tamanho é sempre igual (cpf com 11, uf com 2)
varchar pra nome, código, email
numeric(4,2) pras notas e numeric(5,2) pra frequência, através dos domínios dm_nota (0 a 10) e dm_percentual (0 a 100)
date, time e timestamp pra datas e horários
enum (tp_) pras coisas que só têm algumas opções (turno, status, situação...)

Algumas restrições que vale comentar:

qt_ch_total da disciplina e qt_media_final do histórico são colunas geradas, o próprio banco calcula
o aluno tem uma FK composta (id_curriculo, id_curso) pra garantir que o currículo dele é do curso dele
a tb_turma_horario tem um EXCLUDE que não deixa duas turmas na mesma sala no mesmo horário (usando hr_inicio e hr_fim)
uma disciplina não pode ser pré-requisito dela mesma
cada matrícula tem no máximo um histórico (UNIQUE no id_matricula)
o tb_log_matricula não tem FK de propósito, pra o log continuar existindo se apagarem a matrícula
Como a gente organizou o Git

Combinamos assim:

Não demos commit na main, ela só recebe o que está funcionando
cada um tem sua branch com o nome e a parte que tá fazendo, ex: nome1/modelagem-fisica
commit pequeno, um pra cada parte que funcionou, nada de subir tudo de uma vez
quando uma etapa fica pronta abre um Pull Request pra main e alguém do grupo revisa antes de aceitar
no merge usar "Create a merge commit" e não o Squash, porque o squash junta todos os commits num só e perde o histórico
cada um mexe nos seus arquivos pra não dar conflito

A gente usa o GitHub Desktop. O dia a dia fica mais ou menos assim:

Fetch origin e depois Branch > Update from main (pra pegar o que os outros já subiram)
Faz as alterações e testa no pgAdmin
Escreve a mensagem, Commit e Push origin
Quando terminar uma etapa: Branch > Create pull request, alguém revisa e faz o merge

Pra criar a branch na primeira vez: Current branch > New branch > coloca o nome > Publish branch.

As mensagens de commit a gente tá tentando deixar nesse padrão:

ddl: cria tb_cidade e tb_campus
indice: cria índice parcial nas matrículas ativas
docs: atualiza readme

Se alguém preferir terminal:

git switch -c nome/frente
git pull origin main
git add .
git commit -m "mensagem"
git push
