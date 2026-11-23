# Autores

Banco de Dados II (CCO072), prof. Rodrigo Gonçalves. Cada um cuidou de uma frente. A integração das frentes na main e as revisões finais ficaram com o Arthur, como está descrito no fim deste arquivo; o histórico de quem fez cada commit está no `git log`.

| Integrante | Matrícula | Frente |
|---|---|---|
| Iury Xavier Bomfim | 2412130039 | Modelagem física e desempenho |
| Eduardo Serra | 2412130069 | Transações e concorrência |
| Arthur Coupê | 2512130004 | Administração e operação |

## Iury Xavier Bomfim: modelagem física e desempenho

- `modelo/modelo_conceitual.drawio`: modelo conceitual (DER, notação de Chen) com as 12 entidades, os 15 relacionamentos e a passagem do conceitual para o lógico no rodapé
- `modelo/modelo_logico.drawio`: modelo lógico com as 17 tabelas, tipos, chaves e cardinalidades
- `sql/01_modelo_fisico_v1.sql`: schema `projeto_bd2`, tabelas, domínios, enums, restrições (CHECK, UNIQUE, FK composta, EXCLUDE de horário, colunas geradas)
- `sql/02_testes_restricoes_v1.sql`: testes que provam que as restrições barram dado errado (ampliados na conferência final, ver o fim deste arquivo)
- `sql/03_carga_v1.sql`: carga sintética e determinística (2000 alunos, 1536 turmas, 24.964 matrículas)
- `sql/04_indices_v1.sql`: 4 índices (um parcial) com EXPLAIN antes e depois
- `evidencias/explain_indices_v1.txt` e `evidencias/resumo_indices_v1.csv`

## Eduardo Serra: transações e concorrência

- `sql/05a_concorrencia_preparacao_v1.sql`, `sql/05e_concorrencia_limpeza_v1.sql`
- `sql/05b_concorrencia_erro_v1.sql`: a anomalia da última vaga no READ COMMITTED
- `sql/05c_concorrencia_solucao1_for_update_v1.sql`: solução com trava pessimista (`SELECT ... FOR UPDATE`)
- `sql/05d_concorrencia_solucao2_serializable_v1.sql`: solução com isolamento `SERIALIZABLE` e repetição (erro 40001)
- `evidencias/concorrencia_duas_abas_v1.txt`: as duas abas passo a passo no erro e nas duas soluções

## Arthur Coupê: administração e operação

- `sql/06_consultas_v1.sql`: as 10 consultas comentadas do Marco 1
- `sql/07_administracao_views_v1.sql`: views de oferta, vagas e histórico e a materialized view de indicadores, com a política de refresh e o ganho medido
- `sql/08_administracao_auditoria_v1.sql`: gatilho de auditoria das matrículas e das notas em JSONB, trava contra INSERT direto no log e índice GIN (bônus)
- `sql/09_administracao_seguranca_v1.sql`: papéis, GRANT/REVOKE (inclusive por coluna) e RLS
- `sql/10_administracao_seguranca_testes_v1.sql`: 29 testes de segurança, positivos, negativos e a lista exata do permitido
- `sql/11_administracao_backup_conferencia_v1.sql` e `docs/backup_restauracao.md`: backup, restauração e a impressão digital que prova a restauração
- `evidencias/explain_administracao_v1.txt`, `evidencias/testes_seguranca_v1.txt`, `evidencias/backup_restauracao_v1.txt`

## Revisão final da entrega (22/11, Arthur)

Arthur conferiu a entrega inteira montando o banco do zero pelo README e fez os ajustes que faltavam:

- trouxe para a main o histórico das branches do Iury e do Eduardo, a versão mais nova do diagrama e o `05a_concorrencia_preparacao_v1.sql`, que só existia na branch do Eduardo;
- numerou os scripts na ordem de execução e corrigiu os nomes e os números (36 para 35 vagas) nos comentários, no README e aqui;
- gerou as evidências de índices e de concorrência na rodada do zero e escreveu a comparação entre FOR UPDATE e SERIALIZABLE no README, com as medições X1 a X3;
- conferiu o diagrama v4 do Iury contra o banco e prendeu de novo na coluna certa as 7 linhas que tinham se soltado, com os únicos de mais de uma coluna no rodapé.

Depois dessa revisão, o Iury subiu o modelo conceitual e a versão final do lógico, com o par (mín,máx) escrito junto da entidade que ele descreve, como na Aula 04. Arthur conferiu de novo as 17 tabelas do lógico contra o banco: colunas, tipos e chaves batem.

## Correção depois da apresentação (23/11, Arthur)

Na apresentação o professor apontou o formato dos modelos e o excesso de mínima 0 nas cardinalidades. Arthur fez a correção a partir do modelo do Iury:

- redesenhou os dois diagramas no formato da Aula 04 (fundo branco, cabeçalho do IESB, linhas sem curva e o par nas duas pontas) e trocou a mínima dos pais: 0 só onde a carga tem caso real de pai sem filho, com a contagem de cada caso no README;
- passou os comentários de cardinalidade do `01_modelo_fisico_v1.sql` para o mesmo padrão dos diagramas;
- acrescentou 13 testes ao `02_testes_restricoes_v1.sql` (NOT NULL da FK, UNIQUE da matrícula, do histórico e do CPF, os CHECKs que faltavam, domínio de frequência, enum e coluna gerada) e trocou as conferências que sumiam no F5 por avisos na aba Messages;
- no `04_indices_v1.sql`, o controle que prova que o índice comum não atende o LIKE com a collation do banco;
- no `07` e no `08`, um `COMMIT` antes do bloco de teste, porque no F5 o `ROLLBACK` do teste desfazia também o que o script criou antes dele; e o "semestre atual" das views passou a ser o mais recente cadastrado, como no `06`;
- na evidência de concorrência, as medições X4 (o INSERT com conferência, sem FOR UPDATE, também estoura a turma) e X5 (travas numa turma menor);
- gerou de novo todas as evidências numa rodada do zero e corrigiu o README.

## Conferência final pelos critérios da avaliação (23/11, Arthur)

Arthur rodou o projeto inteiro do zero, conferiu cada número do README contra a saída e cada critério da avaliação, e corrigiu o que é da frente dele e a documentação:

- o `10_administracao_seguranca_testes_v1.sql` ganhou o veredito numa linha só: no fim ele diz "RESULTADO: todos os testes deram OK" ou termina com ERRO dizendo quantos testes falharam, para ninguém ter que contar 29 linhas na aba Messages. Os 24 mutantes foram rodados de novo e todos terminam com ERRO: 23 com o RESULTADO e 1 (o aluno colocado no grupo secretaria) antes dele, num erro de matrícula repetida causado pelo próprio estrago, depois de 8 FALHOU;
- o `07` e o `08` explicam o WARNING "there is no transaction in progress" que aparece no F5;
- a pasta `ferramentas/` guarda os scripts que geram todas as evidências (`rodada_completa.sh`), o F5 do pgAdmin no PostgreSQL 16 e no 17 (`f5_emulacao.sh`), a demonstração das duas abas (`concorrencia_evidencia.py`) e a contagem da cardinalidade mínima (`cardinalidade_minima.sql`), para qualquer um gerar as evidências de novo;
- três evidências novas: o resultado das 10 consultas, as contagens da cardinalidade mínima e a rodada com F5 nas duas versões;
- o README corrige o semestre do aluno 26000002 (é do 2º), o aviso sobre rodar o 03 depois do 08, a descrição dos diagramas e a seção do Git, que agora diz como o histórico ficou de verdade.

Na mesma conferência, Arthur ajustou também pontos das frentes do Iury e do Eduardo:

- o `02_testes_restricoes_v1.sql` passou de 27 para 75 testes de barramento: agora toda restrição CHECK, UNIQUE, FK e EXCLUDE do schema tem teste (cada FK com o pai inexistente), além de PK e NOT NULL, cada teste confere pelo nome que quem barrou foi a restrição esperada e não outra, e o bloco 8 lê o catálogo e dá FALHOU se aparecer restrição nova sem teste. Para provar que os testes pegam o defeito, a rodada monta 72 bancos estragados, cada um com um defeito só (uma das 70 restrições tirada, o NOT NULL da turma tirado ou uma restrição nova sem teste), e confere que o 02 dá FALHOU em todos (`evidencias/testes_restricoes_v1.txt`);
- no `01`, o comentário da P3 explica a regra com um exemplo (a P3 troca a nota que dá a maior média, e não sempre a menor, porque a A2 pesa mais); no `03`, o comentário das salas diz quais ficam sem horário; no `05a`, o semestre dos dois alunos da demonstração;
- a contraprova do `05c` (mostrar que sem o FOR UPDATE a turma estoura) não virou script novo: a medição X4 da evidência de concorrência já prova isso, e mexer na demonstração do Eduardo arriscava o ensaio.
