# DB Manager — Oracle & PostgreSQL (Backup/Restore)

Playbooks de **backup** e **restore** para Oracle (expdp/impdp) e PostgreSQL (pg\_dump/pg\_restore), com:
- Descoberta automática do **dump mais recente** quando `BASE_NAME` não é informado.
- **CIFS** opcional para publicar/consumir dumps.
- **Padrão de e-mail** padronizado (sucesso/erro) igual ao modelo solicitado, com **logs anexados** em caso de falha.
- Suporte a **grants** no Oracle (captura antes do drop e reaplicação após restore).
- Suporte a restore **in-place** ou via **promote** (PostgreSQL).

> Testado em AAP 2.4/2.5. Requer que os binários estejam disponíveis no host de banco (Oracle `expdp/impdp/sqlplus`; PostgreSQL `pg_dump/pg_restore/psql`).

---

## 1) Fluxos suportados

### Oracle
**Backup**
1. Resolve `ORACLE_SID` (via `ORA_SID` ou pmon).
2. Ajusta `ORA_DIR_NAME` para apontar para `BACKUP_DIR`.
3. Gera parfile e executa `expdp`.
4. (Opcional) copia o `.dmp` para CIFS.
5. Envia e-mail **sucesso** (anexa `*.log`) ou **erro** (anexa `*.log` e `*.exp.stderr`).

**Restore**
1. Opcionalmente captura **GRANTs** dos schemas e faz drop dos usuários.
2. Seleciona o dump: **nomeado** (`{{ BACKUP_DIR }}/{{ _base }}.dmp`) ou **mais recente por mtime** em `BACKUP_DIR` (com fallback via CIFS).
3. Executa `impdp` (suporta `nohup` e **aguardo opcional** por conclusão).
4. (Opcional) reaplica **GRANTs** e altera/desbloqueia senhas importadas.
5. Envia e-mail **sucesso** (anexa `*_imp.log` e, se houver, `*_grants.sql`) ou **erro** (anexa consolidado `oracle_restore_error_{{ _base }}.log`).

### PostgreSQL
**Backup**
1. Executa `pg_dump -Fd` gerando `{{ _base }}.dump.dir`.
2. Valida com `pg_restore -l` e grava `{{ _base }}.dump.log`.
3. (Opcional) copia o diretório do dump para CIFS.
4. Envia e-mail **sucesso** (anexa `*.dump.log`) ou **erro** (anexa `*.dump.stderr`).

**Restore**
1. Seleciona o dump: **nomeado** (`{{ BACKUP_DIR }}/{{ _base }}.dump.dir`) ou **mais recente por mtime** (com fallback via CIFS).
2. Cria DB alvo (in-place ou `{{ PG_DB }}_restoring`) e executa `pg_restore` com lista filtrada.
3. (Opcional) promove a base restaurada para o nome original.
4. Envia e-mail **sucesso**/**erro** anexando `pg_restore_{{ _base }}.log`.

---

## 2) Convenções de nomes

- `BASE_NAME` **vazio**: nome é **gerado automaticamente** com timestamp e ID do Job.  
  - Oracle: `ora_<YYYY-MM-DD-HHMMSS>_<jobid>`  
  - PostgreSQL: `pg_<YYYY-MM-DD-HHMMSS>_<jobid>`
- `BASE_NAME` **preenchido**: usado como **prefixo**, e o sistema **acrescenta** sufixo temporal quando aplicável (ex.: `db_teste_2025-11-10-120102_<jobid>`).  
  > Dica: ao definir `BASE_NAME`, os fluxos de **restore** procuram primeiro pelo arquivo/diretório **nomeado** com esse prefixo; se não existir, usam o **mais recente por mtime** no `BACKUP_DIR` (ou no CIFS como fallback).

### Saídas principais
**Oracle (backup):**
- Dump: `{{ _base }}.dmp`
- Log: `{{ _base }}.log`
- Erro do expdp: `{{ _base }}.exp.stderr`

**Oracle (restore):**
- Parfile: `{{ _base }}_imp.par`
- Log do impdp: `{{ _base }}_imp.log`
- nohup/stdout: `imp_{{ _base }}.out` (quando `ORA_NOHUP=true`)
- Grants exportados: `{{ _base }}_grants.sql`
- Erro consolidado (e-mail erro): `oracle_restore_error_{{ _base }}.log`

**PostgreSQL (backup):**
- Diretório do dump: `{{ _base }}.dump.dir`
- Log de validação: `{{ _base }}.dump.log`
- Erro do pg_dump (e-mail erro): `{{ _base }}.dump.stderr`

**PostgreSQL (restore):**
- Lista filtrada: `pg_restore_{{ _base }}.lst`
- Log do restore (anexado em ambos os casos): `pg_restore_{{ _base }}.log`

---

## 3) Seleção de dump no RESTORE (sem `BASE_NAME`)

Quando `BASE_NAME` **não** é informado:
- **Oracle**: escolhe o **arquivo `.dmp` mais recente** por `mtime` em `BACKUP_DIR`. Se habilitado CIFS e nada foi encontrado localmente, busca no CIFS (mais recente), copia para `BACKUP_DIR` e usa.
- **PostgreSQL**: escolhe o **diretório `*.dump.dir` mais recente** por `mtime` em `BACKUP_DIR`. Com CIFS habilitado, mesmo comportamento de fallback.

> Quando `BASE_NAME` **é informado**, os fluxos procuram **primeiro** pelo **artefato nomeado**; se não existir, caem para o **mais recente**.

---

## 4) Variáveis

### Comuns
| Variável | Descrição |
|---|---|
| `DB_HOST` | IP/DNS do host do banco |
| `BACKUP_DIR` | Diretório local dos dumps/logs no host do banco |
| `BASE_NAME` | Prefixo-base dos artefatos. Se vazio, é gerado automaticamente |
| `DB_ACTION` | `backup` ou `restore` |
| `ENABLE_CIFS` | `true/false` para habilitar uso de CIFS |
| `CIFS_MOUNT_DIR` | Ponto de montagem temporário no host do banco |
| `CIFS_PATH` | Caminho dentro do share onde ficam os dumps |
| `CIFS_LABEL` | Chave do mapeamento no dict `send_mail_cifs_address` |
| `send_mail_cifs_address` | Dict com mapeamentos de `LABEL -> //server/share` |
| `cifs_workgroup` | Workgroup/Domínio CIFS |
| `ansible_user` / `ansible_password` | Credenciais para montar CIFS (quando usado) |
| `ansible_url` | URL do AAP/Controller (usada nos e-mails) |

### Oracle
| Variável | Descrição |
|---|---|
| `ORA_OS_USER` | Usuário SO dono do Oracle (ex.: `oracle`) |
| `ORA_SID` | (Opcional) SID; se vazio, detecta via pmon |
| `ORA_PDB` | (Opcional) PDB alvo; pode ser auto-detectado via schema principal |
| `ORA_SCHEMAS` | Lista de schemas a exportar/importar |
| `ORA_DIR_NAME` | Nome do DIRECTORY no Oracle apontando para `BACKUP_DIR` |
| `ORA_NOHUP` | Executa `impdp` em background com `nohup` |
| `ORA_WAIT_IMPORT` | Se `true` e `ORA_NOHUP=true`, aguarda término do import por *poll* |
| `ORA_IMPORT_MAX_POLLS` | Nº máximo de verificações do `impdp` |
| `ORA_IMPORT_POLL_SECONDS` | Intervalo entre verificações (s) |
| `ORA_GRANTS_ENABLE` | Captura/reaplica GRANTs no restore |
| `ORA_NEW_PASSWORD` | Altera e desbloqueia senhas dos usuários importados |
| `ORA_DUMP_EXTRA` | Parâmetros adicionais para `expdp/impdp` |
| `TMP_DIR` | Diretório temporário local p/ relatórios |

### PostgreSQL
| Variável | Descrição |
|---|---|
| `PG_DB` | Base de dados |
| `PG_PORT` | Porta (ex.: 5432) |
| `PG_USER` / `PG_PASSWORD` | Credenciais de acesso |
| `PG_PATH` | Caminho para os binários (ex.: `/usr/pgsql-15/bin`) |
| `PG_OS_USER` | Usuário SO dono dos processos (ex.: `postgres` ou `ansible`) |
| `PG_JOBS` | Paralelismo do `pg_dump` e `pg_restore` |
| `PG_DROP_IN_PLACE` | Se `true`, restaura **in-place** (derruba conexões e recria) |

---

## 5) Padrão de e-mails (backup/restore)

Os e-mails seguem o **mesmo formato das imagens** de exemplo solicitadas:
- **Título**: “Backup/Restore <Motor>”
- **Tabela** com campos essenciais conforme o motor e a ação (sem `SID/PDB` no corpo, seguindo o template da imagem).
- **Link do Job** no AAP: `{{ ansible_url }}/#/jobs/playbook/{{ awx_job_id }}/output`

**Anexos:**
- **Oracle – Backup (erro):** `{{ _base }}.log`, `{{ _base }}.exp.stderr`  
- **Oracle – Backup (sucesso):** `{{ _base }}.log`  
- **Oracle – Restore (erro):** `oracle_restore_error_{{ _base }}.log` (consolida `*_imp.log` e `imp_*.out`)  
- **Oracle – Restore (sucesso):** `{{ _base }}_imp.log` e, se houver, `{{ _base }}_grants.sql`  
- **PostgreSQL – Backup (erro):** `{{ _base }}.dump.stderr`  
- **PostgreSQL – Backup (sucesso):** `{{ _base }}.dump.log`  
- **PostgreSQL – Restore (erro/sucesso):** `pg_restore_{{ _base }}.log`

> **Observação:** Em caso de erro, o **log completo** vai **como anexo** (não é exibido no corpo do e-mail).

---

## 6) Exemplos de execução

### AAP (Survey) — Oracle RESTORE com `BASE_NAME` vazio
```json
{
  "DB_HOST": "192.168.1.10",
  "ORA_SCHEMAS": "PRA_RISKMANAGER",
  "BACKUP_DIR": "/opt/oracle/dumps",
  "ORA_DIR_NAME": "DUMP_DBMANAGER",
  "BASE_NAME": "",
  "ORA_NOHUP": "true",
  "ORA_WAIT_IMPORT": "true",
  "ORA_GRANTS_ENABLE": "true",
  "DB_ACTION": "restore"
}
```
> O play localizará o **.dmp mais recente** por `mtime` em `BACKUP_DIR` (ou no CIFS, se habilitado).

### AAP (Survey) — Oracle BACKUP fixando prefixo
```json
{
  "DB_HOST": "192.168.1.10",
  "ORA_SCHEMAS": "PRA_RISKMANAGER",
  "BACKUP_DIR": "/opt/oracle/dumps",
  "ORA_DIR_NAME": "DUMP_DBMANAGER",
  "BASE_NAME": "db_teste",
  "DB_ACTION": "backup"
}
```
> Os artefatos serão gerados com prefixo **db_teste** (o sistema acrescenta sufixo temporal quando aplicável) e também serão **procurados pelo prefixo** no restore.

### CLI — PostgreSQL BACKUP
```bash
ansible-playbook -i localhost, db_manager_postgresql.yml \
  -e "DB_HOST=10.0.0.5" \
  -e "BACKUP_DIR=/var/backups/pg" \
  -e "PG_DB=erp" -e "PG_USER=postgres" -e "PG_PASSWORD=secret" \
  -e "PG_PORT=5432" -e "PG_PATH=/usr/pgsql-15/bin" \
  -e "BASE_NAME=" -e "DB_ACTION=backup"
```

### CLI — PostgreSQL RESTORE (in-place=false)
```bash
ansible-playbook -i localhost, db_manager_postgresql.yml \
  -e "DB_HOST=10.0.0.5" \
  -e "BACKUP_DIR=/var/backups/pg" \
  -e "PG_DB=erp" -e "PG_USER=postgres" -e "PG_PASSWORD=secret" \
  -e "PG_PORT=5432" -e "PG_PATH=/usr/pgsql-15/bin" \
  -e "PG_DROP_IN_PLACE=false" \
  -e "BASE_NAME=" -e "DB_ACTION=restore"
```

---

## 7) CIFS — requisitos e fluxo

1. Preencha `ENABLE_CIFS=true`, `CIFS_MOUNT_DIR`, `CIFS_PATH`, `CIFS_LABEL`, `cifs_workgroup`, `ansible_user`, `ansible_password` e o dict `send_mail_cifs_address`.
2. O play monta o share durante a execução e **desmonta** ao final.
3. **Backup** copia o artefato local → CIFS. **Restore** tenta **buscar** primeiro o nomeado no CIFS e, se não houver, pega o **mais recente** e copia para `BACKUP_DIR`.

---

## 8) Segurança & Operação

- **Permissões**: garanta `BACKUP_DIR` com permissões corretas para o usuário do S.O. (`ORA_OS_USER`/`PG_OS_USER`).  
- **Oracle DIRECTORY**: o usuário do Oracle precisa permissão para o `ORA_DIR_NAME` que aponta para `BACKUP_DIR`.  
- **Senhas**: variáveis sensíveis devem usar `no_log: true` nos templates do AAP.  
- **Network**: verifique conectividade, Firewalld e SELinux para montagem CIFS e acesso ao banco.  

---

## 9) Estrutura dos playbooks (resumo)

```
oracle/
  db_manager_oracle.yml        # orquestração (backup/restore)
  tasks/
    backup.yml                 # expdp, logs, CIFS, e-mail
    restore.yml                # grants, seleção dump, impdp, CIFS, e-mail
  defaults/main.yml            # variáveis padrão (Oracle)

postgresql/
  db_manager_postgresql.yml    # orquestração (backup/restore)
  tasks/
    backup.yml                 # pg_dump, validação, CIFS, e-mail
    restore.yml                # seleção dump, pg_restore, promote, e-mail
  defaults/main.yml            # variáveis padrão (PostgreSQL)
```

---

## 10) Troubleshooting

- **Oracle**: `ORA-39002/39070/39087` — verifique `ORA_DIR_NAME`, permissões do filesystem e espaço em disco.  
- `expdp: command not found` — garanta `ORACLE_HOME/bin` no `PATH` e `oraenv` configurado.  
- **PostgreSQL**: `pg_restore: error:` — valide compatibilidade de versão entre origem/target.  
- **CIFS**: “operation not permitted” — verifique credenciais, `vers=3.0`, DNS/roteamento e SELinux (`setenforce 0` para teste).  
- **E-mails vazios/sem anexo** — garanta que os caminhos de logs estão sendo gerados e que `send_mail_*` da sua stack de e-mail está configurado.

---

## 11) Changelog (resumo)

- **Nov/2025**: Padronização de e-mails (sucesso/erro) conforme template solicitado, com **logs em anexo** nas falhas; seleção do **dump mais recente por mtime** quando `BASE_NAME` vazio (Oracle e PostgreSQL).

---

© 2025 — Automação DB Manager (Oracle & PostgreSQL) — Alex Maxwell & Equipe
