# SQL Server Patch Manager

Playbook que realiza **aplicação de patch em SQL Server no Windows**, suportando dois cenários:

- **standalone**
- **Always On Availability Group (AG)**

A automação foi construída para operar próxima do padrão do cliente:

- seleção de alvos por **`survey_hosts`**
- uso de **named instance**
- autenticação **Integrated / Windows**
- consultas SQL via **`Invoke-Sqlcmd`**
- descoberta dinâmica de **PRIMARY** e **SECONDARY**
- patch em AG com ordem controlada:
  - **secondaries pré-failover**
  - **failover**
  - **primary original** (agora secondary)
- **espera de estabilização do AG** entre etapas críticas
- geração de **relatório HTML** consolidado

> Observação: o envio SMTP é feito por **job separado**. Este play publica `send_mail_subject` e `send_mail_body` para o job de e-mail.

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `survey_hosts` | string\|list | Hosts informados no survey. Pode ser string com vírgulas (`"srv1,srv2"`) ou lista YAML. |
| `sql_topology` | string | Topologia do alvo: `single` ou `ag_cluster`. |
| `sql_instance_name` | string | **Named instance** do SQL Server. Ex.: `SQLPRD13`, `SQLLAB13`, `BBI01`, `TFS01`. |
| `motivo` | string | Texto exibido no cabeçalho do relatório. |
| `sql_environment` | string | Ambiente exibido no relatório. Ex.: `hml`, `prd`. |
| `sql_precheck_only` | bool | Quando `true`, executa apenas discovery + precheck + report, sem aplicar patch. |
| `ag_expand_to_all_nodes` | bool | Quando `true`, a automação descobre o AG e expande o escopo para todos os nós. |
| `ag_allow_partial_patch` | bool | Permite patch parcial em AG. Ex.: apenas uma secondary ou apenas a primary com failover. |
| `ag_failover_preferred_regex` | string | Regex para preferir a secondary candidata ao failover. Ex.: `-MZ-`. |
| `ag_failover_enabled` | bool | Habilita o failover planejado quando a primary está no escopo. |
| `ag_failback_to_original_primary` | bool | Quando `true`, faz failback ao final do fluxo. |
| `ag_auto_add_failover_candidate_when_primary_selected` | bool | Se a primary original estiver no escopo, adiciona automaticamente a secondary candidata ao plano pré-failover. |
| `sql_query_timeout_seconds` | int | Timeout de cada chamada SQL (`Invoke-Sqlcmd`). |
| `ag_health_wait_timeout_seconds` | int | Tempo total máximo para aguardar o AG voltar a saudável após patch/failover. |
| `ag_health_poll_interval_seconds` | int | Intervalo entre as checagens de saúde do AG. |
| `patch_cifs_share` | string | Share CIFS onde o patch já está disponível. |
| `patch_package_name` | string | Nome do executável do patch. Ex.: `SQLServer2022-KB5080999-x64.exe`. |
| `patch_cifs_username` / `patch_cifs_password` | string | Credenciais de acesso ao share CIFS. |

### Regras de negócio principais

- **Antes do patch**: se o AG vier **não saudável**, a automação **falha e não segue**.
- **Depois de patch/failover**: a automação **não falha de primeira**; ela aguarda o AG voltar a saudável dentro da janela configurada.
- Quando a **primary original** está no escopo, a automação:
  1. escolhe uma **secondary candidata** saudável
  2. patcha essa candidata (se necessário)
  3. faz **failover**
  4. patcha a **primary original**, agora como secondary

---

## 2. Estrutura esperada

- **entrada por survey**: `survey_hosts` define os hosts iniciais.
- **registro dinâmico**: os hosts são adicionados dinamicamente com `add_host`.
- **discovery SQL**: `30_discover_sql_topology.yml` identifica:
  - host standalone ou AG
  - nome do AG
  - PRIMARY atual
  - secondaries
  - topologia completa
- **precheck**:
  - `32_precheck_single.yml` para standalone
  - `33_precheck_ag.yml` para AG
- **patch em AG**:
  - `43_patch_ag.yml` coordena a ordem real do patch
  - `42_failover_to_candidate.yml` executa o failover
  - `44_wait_ag_healthy.yml` aguarda estabilização do AG
- **pós-check**:
  - `50_postcheck_sql.yml` coleta a versão final
- **report**:
  - `60_build_report.yml` publica `send_mail_subject` e `send_mail_body`

### Fluxo AG (ordem real)

1. discovery do AG  
2. precheck na PRIMARY  
3. patch nas secondaries pré-failover  
4. espera o AG ficar saudável  
5. failover para a secondary candidata  
6. espera o AG ficar saudável  
7. patch da primary original (agora secondary)  
8. espera o AG ficar saudável  
9. failback opcional  
10. pós-check + report

### Fluxo standalone

1. discovery local  
2. precheck  
3. patch  
4. pós-check  
5. report

---

## 3. YAML de exemplo

### 3.1 Standalone com patch real

```yaml
survey_hosts: "LAB-SQL-SGL-01"
sql_topology: "single"
sql_instance_name: "SQLLAB01"
motivo: "Patch standalone SQL"
sql_environment: "hml"

sql_precheck_only: false

patch_cifs_share: "//192.168.0.115/certs/sql-patchs"
patch_package_name: "SQLServer2022-KB5080999-x64.exe"
patch_cifs_username: "192.168.0.115\\ansible"
patch_cifs_password: "********"
```

### 3.2 AG apenas precheck

```yaml
survey_hosts: "LAB-MZ-SQL-01"
sql_topology: "ag_cluster"
sql_instance_name: "SQLLAB13"
motivo: "Precheck AG"
sql_environment: "hml"

sql_precheck_only: true
ag_expand_to_all_nodes: true
ag_allow_partial_patch: true
ag_failover_preferred_regex: "-MZ-"
ag_failover_enabled: true
```

### 3.3 AG full patch

```yaml
survey_hosts: "LAB-MZ-SQL-01"
sql_topology: "ag_cluster"
sql_instance_name: "SQLLAB13"
motivo: "Patch full AG"
sql_environment: "hml"

sql_precheck_only: false
ag_expand_to_all_nodes: true
ag_allow_partial_patch: true
ag_failover_preferred_regex: "-MZ-"
ag_failover_enabled: true
ag_failback_to_original_primary: false
ag_auto_add_failover_candidate_when_primary_selected: true

sql_query_timeout_seconds: 300
ag_health_wait_timeout_seconds: 3600
ag_health_poll_interval_seconds: 60

patch_cifs_share: "//192.168.0.115/certs/sql-patchs"
patch_package_name: "SQLServer2022-KB5080999-x64.exe"
patch_cifs_username: "192.168.0.115\\ansible"
patch_cifs_password: "********"
```

### 3.4 AG parcial em uma secondary

```yaml
survey_hosts: "LAB-MZ-SQL-02"
sql_topology: "ag_cluster"
sql_instance_name: "SQLLAB13"
motivo: "Patch parcial secondary"
sql_environment: "hml"

sql_precheck_only: false
ag_expand_to_all_nodes: false
ag_allow_partial_patch: true
ag_failover_enabled: true

patch_cifs_share: "//192.168.0.115/certs/sql-patchs"
patch_package_name: "SQLServer2022-KB5080999-x64.exe"
patch_cifs_username: "192.168.0.115\\ansible"
patch_cifs_password: "********"
```

---

## 4. Execução (CLI)

```bash
# Standalone
ansible-playbook -i localhost, playbook.yml \
  -e "survey_hosts=LAB-SQL-SGL-01" \
  -e "sql_topology=single" \
  -e "sql_instance_name=SQLLAB01" \
  -e "motivo=Patch standalone"

# AG - precheck only
ansible-playbook -i localhost, playbook.yml \
  -e "survey_hosts=LAB-MZ-SQL-01" \
  -e "sql_topology=ag_cluster" \
  -e "sql_instance_name=SQLLAB13" \
  -e "sql_precheck_only=true" \
  -e "ag_expand_to_all_nodes=true" \
  -e "motivo=Precheck AG"

# AG - full patch
ansible-playbook -i localhost, playbook.yml \
  -e "survey_hosts=LAB-MZ-SQL-01" \
  -e "sql_topology=ag_cluster" \
  -e "sql_instance_name=SQLLAB13" \
  -e "sql_precheck_only=false" \
  -e "ag_expand_to_all_nodes=true" \
  -e "motivo=Patch full AG"
```

> No AAP, as variáveis são preenchidas pelo Survey do template **SQL Patch Manager**; o envio de e-mail roda em job separado usando os artefatos publicados.

---

## 5. Saída

### SUCESSO
Quando o fluxo termina corretamente, o relatório HTML traz:

- resumo da execução
- estado inicial do AG
- precheck
- estado final do AG
- ações executadas
- pós-check com versão final por host

### FALHA
Quando ocorre falha, o relatório/e-mail indica:

- task que falhou
- mensagem de erro
- momento da falha
- e o fluxo é interrompido

### Evidências coletadas

- discovery inicial
- PRIMARY / SECONDARY antes e depois
- health do AG
- Remote Registry no cluster
- ações executadas (patch, failover, espera do AG saudável)
- versão final do SQL Server em cada host

---

## 6. Tasks principais

| Task | Função |
| --- | --- |
| `00_validate_inputs.yml` | Valida entradas obrigatórias e inicializa o `patch_report`. |
| `10_plan_targets.yml` | Normaliza `survey_hosts` e monta o plano inicial de execução. |
| `11_register_seed_hosts.yml` | Registra dinamicamente os hosts do survey para WinRM. |
| `20_mount_cifs.yml` | Monta o CIFS e localiza o pacote de patch. |
| `30_discover_sql_topology.yml` | Faz o discovery SQL/AG e descobre a topologia real. |
| `31_remote_registry_prepare.yml` | Garante `RemoteRegistry` em todos os nós do AG. |
| `32_precheck_single.yml` | Precheck do cenário standalone. |
| `33_precheck_ag.yml` | Precheck do AG com fail-fast antes do patch. |
| `34_register_ag_hosts.yml` | Registra todos os nós descobertos do AG. |
| `41_patch_one_host.yml` | Aplica patch em um host específico. |
| `42_failover_to_candidate.yml` | Executa o failover planejado para a réplica candidata. |
| `43_patch_ag.yml` | Coordena o fluxo completo do patch em AG. |
| `44_wait_ag_healthy.yml` | Aguarda o AG voltar a saudável após patch/failover. |
| `50_postcheck_sql.yml` | Coleta a versão final do SQL Server. |
| `60_build_report.yml` | Renderiza o HTML e publica os dados para envio de e-mail. |

---

## 7. Observações de laboratório

No lab atual, alguns pontos foram adaptados por causa do AAP rodando em **CRC/OpenShift**:

- preservação de `ansible_host` com IP real
- uso de `Invoke-Sqlcmd -TrustServerCertificate`
- patch puxado via SMB pelo Windows alvo
- fluxo ajustado para named instance em ambiente de teste

Esses ajustes são úteis no laboratório, mas alguns detalhes podem ser refinados para o ambiente final do cliente.

---

## 8. Resultado esperado do fluxo AG

Em um patch full AG, o comportamento esperado é:

- **estado inicial**:
  - 1 nó como `PRIMARY`
  - demais como `SECONDARY`
- patch das secondaries
- failover para a candidata
- patch da primary original
- **estado final**:
  - nova PRIMARY ativa
  - réplicas secundárias conectadas e healthy
- pós-check com versão final atualizada em todos os nós

---

## 9. Resumo executivo

A automação não apenas executa o patch.  
Ela também:

- descobre a topologia real do SQL Server
- valida se o ambiente está saudável antes de começar
- decide a ordem correta do patch no AG
- executa failover quando necessário
- aguarda estabilização entre etapas críticas
- valida o resultado final
- gera evidência consolidada em HTML

Isso garante mais segurança e previsibilidade para patch em SQL Server standalone e em Always On AG.
