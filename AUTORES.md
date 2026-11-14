# Autores

Banco de Dados II (CCO072), prof. Rodrigo Gonçalves. Cada um cuidou de uma frente e todos revisam os Pull Requests dos outros antes do merge.

| Integrante | Matrícula | Frente |
|---|---|---|
| Iury Xavier Bomfim | 2412130039 | Modelagem física e desempenho |
| Eduardo Serra | 2412130069 | Transações e concorrência |
| Arthur Coupê | 2512130004 | Administração e operação |

## Iury Xavier Bomfim: modelagem física e desempenho

- `modelo/modelo_logico.v3.drawio`: modelo lógico com as 17 tabelas, tipos, chaves e cardinalidades
- `sql/modelo_fisico_v1.sql`: schema `projeto_bd2`, tabelas, domínios, enums, restrições (CHECK, UNIQUE, FK composta, EXCLUDE de horário, colunas geradas)
- `sql/testes_restricoes_v1.sql`: 14 testes que provam que as restrições barram dado errado
- `sql/carga_v1.sql`: carga sintética e determinística (2000 alunos, 1536 turmas, ~25 mil matrículas)
- `sql/indices_v1.sql`: 4 índices (um parcial) com EXPLAIN antes e depois
- `evidencias/explain_indices_v1.txt` e `evidencias/resumo_indices_v1.csv`

## Eduardo Serra: transações e concorrência

- `sql/concorrencia_preparacao_v1.sql`, `sql/concorrencia_limpeza_v1.sql`
- `sql/concorrencia_erro_v1.sql`: a anomalia da última vaga no READ COMMITTED
- `sql/concorrencia_solucao1_for_update_v1.sql`: solução com trava pessimista (`SELECT ... FOR UPDATE`)
- `sql/concorrencia_solucao2_serializable_v1.sql`: solução com isolamento `SERIALIZABLE` e repetição (erro 40001)
- prints da demonstração em `evidencias/`

## Arthur Coupê: administração e operação

- `sql/consultas_v1.sql`: as 10 consultas comentadas do Marco 1
- `sql/administracao_views_v1.sql`: views de oferta, vagas e histórico e a materialized view de indicadores, com a política de refresh e o ganho medido
- `sql/administracao_auditoria_v1.sql`: gatilho de auditoria das matrículas e das notas em JSONB, trava contra INSERT direto no log e índice GIN (bônus)
- `sql/administracao_seguranca_v1.sql`: papéis, GRANT/REVOKE (inclusive por coluna) e RLS
- `sql/administracao_seguranca_testes_v1.sql`: 29 testes de segurança, positivos, negativos e a lista exata do permitido
- `sql/administracao_backup_conferencia_v1.sql` e `docs/backup_restauracao.md`: backup, restauração e a impressão digital que prova a restauração
- `evidencias/explain_administracao_v1.txt`, `evidencias/testes_seguranca_v1.txt`, `evidencias/backup_restauracao_v1.txt`
