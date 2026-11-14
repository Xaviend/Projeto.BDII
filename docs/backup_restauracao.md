# Backup e restauração

Autor: Arthur Coupê (Administração e Operação)

Este é o procedimento de backup do schema `projeto_bd2` (banco `matricula`) e de restauração, do jeito que mostramos na apresentação. Ele foi ensaiado do começo ao fim no PostgreSQL 16, num banco com um schema `academico` simulado ao lado (como o do professor), em quatro situações:

1. restauração num banco separado (`matricula_restaurada`), para conferir o backup sem mexer no original;
2. desastre total: o schema `projeto_bd2` apagado e restaurado no mesmo banco;
3. erro humano: matrículas canceladas e linhas do log apagadas, e volta ao backup;
4. servidor novo, vazio, recebendo só os arquivos de backup.

Nas quatro, a impressão digital (`sql/administracao_backup_conferencia_v1.sql`) deu igual à de antes do backup, e os 22 testes de segurança (`sql/administracao_seguranca_testes_v1.sql`) passaram depois da restauração.

## O que é o quê

| Arquivo | O que guarda | Comando |
|---|---|---|
| `matricula.dump` | o schema `projeto_bd2` inteiro: tabelas, dados, índices, views, materialized view, funções, gatilho, policies de RLS e GRANTs | `pg_dump -n projeto_bd2 -Fc` |
| `papeis.sql` | os papéis (aluno, secretaria, coordenacao, aluno_26000001, aluno_26000012), **sem senha** | `pg_dumpall --roles-only --no-role-passwords` |

Por que dois arquivos: papel (role) não pertence a um banco, pertence ao servidor inteiro. O `pg_dump` guarda os GRANTs e as policies que citam os papéis, mas não cria os papéis. No mesmo servidor eles já existem. Num servidor novo, o `papeis.sql` roda antes.

Por que só o schema `projeto_bd2` (`-n`): o banco `matricula` do professor também tem o schema `academico`, que não é nosso. Com o banco inteiro no backup, a restauração tentaria recriar o `academico` por cima do que já existe e pararia com "already exists". Com `-n` o backup leva só o projeto e a restauração não encosta no `academico`. O que o `-n` não leva é a extensão `btree_gist` (ela fica no schema `public`, e o EXCLUDE de horário da `tb_turma_horario` precisa dela): num banco novo ela é criada antes da restauração (casos A e D).

Por que `-Fc` (formato custom): é compactado e o `pg_restore` consegue escolher o que restaurar e em que ordem. O formato texto (`.sql`) também funciona, mas é maior e só restaura tudo de uma vez.

Por que `--no-role-passwords`: sem isso o arquivo leva o hash da senha do `bd2`. Hash de senha é credencial e não vai para o Git nem para a nuvem. A pasta `backup/` está no `.gitignore` por isso (e porque backup de banco não é código).

Por que rodar dentro do container (`docker exec`) e não no Windows: o `pg_dump` precisa ser da mesma versão do servidor ou mais nova, e o do container é exatamente a do servidor. E no PowerShell, mandar a saída do `pg_dump` com `>` para um arquivo estraga o arquivo binário. Com `-f` o arquivo é gravado dentro do container e o `docker cp` copia ele inteiro.

## Antes de começar

- Docker Desktop aberto e o container `bd2_postgres` com status Up (`docker compose ps` na pasta do ambiente do professor).
- Terminal aberto na pasta do repositório (`Projeto.BDII`). Os comandos abaixo funcionam igual no PowerShell e no Git Bash.
- Criar a pasta do backup (uma vez só):

```bash
mkdir backup
```

## 1. Tirar a impressão digital (antes)

No pgAdmin, banco `matricula`, abrir `sql/administracao_backup_conferencia_v1.sql` e rodar com F5. Guardar (print ou anotar) a última linha, `>>> IMPRESSAO DIGITAL GERAL`: são o total de linhas e um código md5 de 32 letras.

## 2. Fazer o backup

```bash
docker exec bd2_postgres sh -c "pg_dump -U bd2 -d matricula -n projeto_bd2 -Fc -f /tmp/matricula.dump"
```

```bash
docker exec bd2_postgres sh -c "pg_dumpall -U bd2 --roles-only --no-role-passwords -f /tmp/papeis.sql"
```

```bash
docker cp bd2_postgres:/tmp/matricula.dump backup/matricula.dump
```

```bash
docker cp bd2_postgres:/tmp/papeis.sql backup/papeis.sql
```

Conferir que os dois arquivos estão na pasta `backup/` e que o `.dump` não está vazio (tem cerca de 1,2 MB com a carga do projeto):

```bash
ls backup
```

## 3. Restaurar

Escolha o caso.

### Caso A: conferir o backup num banco separado (não mexe no original)

```bash
docker exec bd2_postgres sh -c "dropdb -U bd2 --if-exists matricula_restaurada && createdb -U bd2 matricula_restaurada"
```

```bash
docker exec bd2_postgres sh -c "psql -U bd2 -d matricula_restaurada -c 'CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;'"
```

```bash
docker exec bd2_postgres sh -c "pg_restore -U bd2 -d matricula_restaurada --exit-on-error /tmp/matricula.dump"
```

Sem a extensão, o `pg_restore` para com `data type integer has no default operator class for access method "gist"` (é o EXCLUDE de horário pedindo o `btree_gist`).

No pgAdmin, clicar com o botão direito em Databases > Refresh, abrir o Query Tool no banco `matricula_restaurada` e rodar o `administracao_backup_conferencia_v1.sql`. A última linha tem que ser igual à do passo 1.

### Caso B: o schema sumiu (desastre total)

Simulação do desastre, no Query Tool do banco `matricula`:

```sql
DROP SCHEMA projeto_bd2 CASCADE;
SELECT count(*) FROM projeto_bd2.tb_aluno;   -- erro: relation "projeto_bd2.tb_aluno" does not exist
```

Restauração (sem `--clean`, porque não sobrou nada para apagar):

```bash
docker exec bd2_postgres sh -c "pg_restore -U bd2 -d matricula --exit-on-error /tmp/matricula.dump"
```

Rodar a impressão digital no `matricula`: igual à do passo 1. O schema `academico` do professor não é tocado.

### Caso C: alguém alterou ou apagou dados e queremos voltar ao backup

O schema ainda existe, então o `pg_restore` apaga cada objeto e recria a partir do backup:

```bash
docker exec bd2_postgres sh -c "pg_restore -U bd2 -d matricula --clean --if-exists --exit-on-error /tmp/matricula.dump"
```

Cuidado: tudo que foi gravado depois do backup se perde. Não use `--clean` no caso B: com o schema já apagado ele para com o erro `schema "projeto_bd2" does not exist`.

### Caso D: servidor novo, vazio

Copiar os arquivos para dentro do container novo e criar os papéis antes:

```bash
docker cp backup/matricula.dump bd2_postgres:/tmp/matricula.dump
```

```bash
docker cp backup/papeis.sql bd2_postgres:/tmp/papeis.sql
```

```bash
docker exec bd2_postgres sh -c "psql -U bd2 -d matricula -f /tmp/papeis.sql"
```

Aparece `ERROR: role "bd2" already exists`: é esperado (o `bd2` foi criado junto com o container) e o resto do arquivo roda normalmente.

```bash
docker exec bd2_postgres sh -c "psql -U bd2 -d matricula -c 'CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;'"
```

```bash
docker exec bd2_postgres sh -c "pg_restore -U bd2 -d matricula --exit-on-error /tmp/matricula.dump"
```

## 4. Conferir depois

1. Impressão digital igual à do passo 1 (a linha `>>> IMPRESSAO DIGITAL GERAL`).
2. `sql/administracao_seguranca_testes_v1.sql` com F5: 22 linhas `OK` e nenhuma `FALHOU` na aba Messages. Isso prova que os papéis, os GRANTs e o RLS voltaram junto com os dados.

O que a impressão digital compara: quantidade de linhas e md5 do conteúdo de cada tabela e da materialized view, e a estrutura (views, índices, policies, RLS ligado, gatilho, funções e permissões). A coluna `dt_atualizacao` da `mv_indicadores` fica fora, porque a restauração recalcula a materialized view e essa coluna guarda a hora do cálculo.

## Perguntas que podem cair

- **Backup lógico ou físico?** Lógico: o `pg_dump` gera os comandos e os dados para recriar o banco. O físico copia os arquivos do disco do servidor (`pg_basebackup`) e serve para recuperar até um instante exato (PITR), junto com o WAL. Para o projeto o lógico basta e é o que dá para levar de uma máquina para outra.
- **O `pg_dump` trava o banco?** Não para leitura nem escrita comum. Ele roda numa transação só (o retrato do banco no começo do dump), então o backup é consistente mesmo com gente matriculando durante o dump. Só bloqueia quem tenta mudar a estrutura (ALTER TABLE, DROP) das tabelas enquanto ele roda.
- **E o RLS no backup?** O `pg_dump` roda como `bd2`, que é superusuário e enxerga todas as linhas. Se rodasse com um papel sujeito ao RLS, o `pg_dump` pararia com erro em vez de gerar um backup faltando linhas.
- **Com que frequência?** Numa faculdade de verdade: backup lógico diário (de madrugada, junto com o `REFRESH` da materialized view) e backup físico contínuo com WAL. O backup só vale se a restauração for testada, que é o que o caso A faz.
