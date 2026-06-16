# Data Purge Manager

Automação Ansible para **expurgo controlado de arquivos antigos** em servidores Linux e Windows, com execução em modo `check` ou `apply`, validação de segurança de paths, regras por grupo/ambiente, detecção dinâmica de sistema operacional e geração de relatórios operacionais e gerenciais.

A solução é composta por dois fluxos:

- **Data Purge Manager**: executa o planejamento, validação, check/apply, auditoria e relatório operacional.
- **Data Purge Metrics Report**: executa em schedule separado para gerar relatório mensal ou anual de economia com base nos JSONs de métrica.

---

## 1. Workflow operacional de expurgo

Exemplo de workflow:

```text
WF_Devops_Data_Purge_Manager
  ├── MCA_Data_Purge_Manager
  └── Test_Send_Email
```

O template `MCA_Data_Purge_Manager` executa o playbook `purge_manager.yml` e a role `data_purge_manager`.

Principais capacidades:

- seleção por grupo, ambiente e hosts informados no survey;
- detecção automática Linux/Windows por SSH/WinRM;
- execução de regras Linux apenas em hosts Linux;
- execução de regras Windows apenas em hosts Windows;
- suporte a grupo misto com regras Linux e Windows;
- execução em modo `check` sem remoção;
- execução em modo `apply` com confirmação explícita;
- bloqueio de paths perigosos por `forbidden_paths` e `allowed_prefixes`;
- engine por regra: `modules` ou `shell`;
- geração de relatório HTML operacional;
- geração de TXT de auditoria por host em `apply`;
- geração de JSON de métrica por execução `apply` com remoção real.

---

## 2. Variáveis principais do expurgo

| Variável                     | Exemplo            | Descrição                                             |
| ---------------------------- | ------------------ | ----------------------------------------------------- |
| `motivo`                     | `Expurgo mensal`   | Justificativa da execução exibida no relatório.       |
| `purge_applications`         | `sinacor,inoa`     | Grupos selecionados para execução.                    |
| `purge_env`                  | `prd`              | Ambiente ou ambientes selecionados.                   |
| `survey_hosts`               | `host01,host02`    | Filtro opcional de hosts dentro do escopo resolvido.  |
| `purge_mode`                 | `check` ou `apply` | Define se apenas lista candidatos ou executa remoção. |
| `purge_confirm_delete`       | `sim` ou `nao`     | Confirmação obrigatória para remoção real em `apply`. |
| `purge_include_global_rules` | `sim` ou `nao`     | Define se regras globais entram no plano.             |

Para remover arquivos, as duas condições precisam ser verdadeiras:

```yaml
purge_mode: apply
purge_confirm_delete: sim
```

---

## 3. Segurança

A automação valida os paths antes de listar ou remover arquivos.

| Variável                                  | Descrição                                                   |
| ----------------------------------------- | ----------------------------------------------------------- |
| `purge_forbidden_paths_linux`             | Lista de paths Linux proibidos, como `/`, `/etc`, `/var`.   |
| `purge_forbidden_paths_windows`           | Lista de paths Windows proibidos, como `C:\`, `C:\Windows`. |
| `purge_min_path_length_linux`             | Tamanho mínimo aceito para paths Linux.                     |
| `purge_min_path_length_windows`           | Tamanho mínimo aceito para paths Windows.                   |
| `purge_enforce_allowed_prefixes`          | Valida se os paths estão dentro dos prefixos permitidos.    |
| `purge_allowed_prefixes_required`         | Exige `allowed_prefixes` para permitir execução da regra.   |
| `purge_allow_survey_hosts_outside_matrix` | Controla se hosts fora da matriz podem ser considerados.    |
| `purge_allow_multi_env_apply`             | Controla se `apply` pode rodar em múltiplos ambientes.      |

Recomendação para produção:

```yaml
purge_enforce_allowed_prefixes: true
purge_allowed_prefixes_required: true
purge_allow_survey_hosts_outside_matrix: false
purge_allow_multi_env_apply: false
```

---

## 4. Regras de expurgo

As regras ficam nos arquivos de grupo em:

```text
config/purge_manager/apps/*.yml
```

Exemplo simplificado:

```yaml
name: sinacor
allowed_prefixes:
  linux:
    - /opt/sinacor
  windows:
    - D:\SINACOR

rules:
  linux:
    - name: sinacor_linux_logs_30d
      description: Remove logs Linux antigos
      paths:
        - /opt/sinacor/logs
      patterns:
        - "*.log"
      exclude_patterns:
        - "keep-*"
      age_days: 30
      recursive: true
      delete_empty_dirs: false
      enabled: true
      engine: modules

  windows:
    - name: sinacor_windows_logs_30d
      description: Remove logs Windows antigos
      paths:
        - D:\SINACOR\logs
      patterns:
        - "*.log"
      age_days: 30
      recursive: true
      delete_empty_dirs: false
      enabled: true
      engine: modules
```

Campos principais:

| Campo               | Descrição                                         |
| ------------------- | ------------------------------------------------- |
| `name`              | Nome único da regra.                              |
| `hosts`             | Lista opcional de hosts específicos para a regra. |
| `paths`             | Diretórios onde a busca será realizada.           |
| `patterns`          | Padrões de arquivos elegíveis.                    |
| `exclude_patterns`  | Padrões protegidos que não devem ser removidos.   |
| `age_days`          | Idade mínima em dias.                             |
| `recursive`         | Define se a busca percorre subdiretórios.         |
| `delete_empty_dirs` | Remove diretórios vazios após o expurgo.          |
| `enabled`           | Habilita ou desabilita a regra.                   |
| `engine`            | `modules` ou `shell`.                             |

---

## 5. Engines de execução

| Engine    | Uso recomendado                                                                                        |
| --------- | ------------------------------------------------------------------------------------------------------ |
| `modules` | Padrão recomendado. Usa módulos Ansible, é mais rastreável e indicado para volumes pequenos ou médios. |
| `shell`   | Usa shell/PowerShell controlado, indicado para regras de alto volume ou diretórios recursivos grandes. |

A engine `shell` não executa comandos livres definidos pelo operador. A regra continua declarativa, usando apenas campos como `paths`, `patterns`, `exclude_patterns`, `age_days`, `recursive` e `delete_empty_dirs`.

Recomendação:

```yaml
purge_engine_default: modules
```

Use `engine: shell` somente em regras que realmente exigem performance.

---

## 6. Artefatos gerados pelo expurgo

Em cada execução, o Data Purge Manager publica as variáveis de e-mail:

```yaml
send_mail_subject: "Assunto do e-mail"
send_mail_body: "HTML do relatório"
```

Em modo `apply`, quando há remoção real, também podem ser gerados:

| Artefato                              | Descrição                                                                   |
| ------------------------------------- | --------------------------------------------------------------------------- |
| TXT de auditoria por host             | Lista arquivos removidos, host, SO, regra, data/hora e tamanho removido.    |
| `data_purge_metric_YYYYMM_JOBID.json` | JSON de métrica da execução, usado pelo relatório mensal/anual de economia. |

Exemplo de métrica:

```text
data_purge_metric_202606_7280.json
```

Os JSONs de métrica são armazenados no CIFS em:

```text
/Ansible/data_purge_metrics
```

---

## 7. Workflow de relatório mensal/anual

Exemplo de workflow:

```text
WF_Devops_Data_Purge_Metrics
  ├── MCA_Data_Purge_Metrics
  └── Test_Send_Email
```

O template `MCA_Data_Purge_Metrics` executa:

```text
savings_monthly_report.yml
```

Esse playbook lê os JSONs de métrica no CIFS, consolida os dados e gera o relatório de economia mensal ou anual.

---

## 8. Variáveis do relatório de economia

| Variável                                         | Exemplo                       | Descrição                                                             |
| ------------------------------------------------ | ----------------------------- | --------------------------------------------------------------------- |
| `savings_report_period`                          | `monthly` ou `annual`         | Define se o relatório será mensal ou anual.                           |
| `savings_report_month`                           | `202606`                      | Mês manual no formato `YYYYMM`. Quando preenchido, tem prioridade.    |
| `savings_report_month_mode`                      | `previous`                    | Usa `current` ou `previous` quando `savings_report_month` está vazio. |
| `savings_report_year`                            | `2026`                        | Ano manual no formato `YYYY`. Quando preenchido, tem prioridade.      |
| `savings_report_year_mode`                       | `previous`                    | Usa `current` ou `previous` quando `savings_report_year` está vazio.  |
| `savings_metrics_cifs_path`                      | `/Ansible/data_purge_metrics` | Caminho CIFS onde ficam as métricas.                                  |
| `savings_consolidate_month`                      | `true`                        | Gera `data_purge_monthly_YYYYMM.json`.                                |
| `savings_prefer_monthly_consolidated`            | `true`                        | Usa consolidado mensal quando já existir.                             |
| `savings_delete_raw_after_monthly_consolidation` | `false`                       | Remove os brutos do mês após consolidar. Manter `false` inicialmente. |
| `savings_consolidate_year`                       | `true`                        | Gera `data_purge_yearly_YYYY.json`.                                   |
| `savings_prefer_yearly_consolidated`             | `true`                        | Usa consolidado anual quando já existir.                              |
| `savings_annual_fallback_to_raw`                 | `true`                        | No anual, busca arquivos brutos se faltar consolidado mensal.         |

---

## 9. Funcionamento do relatório mensal

O relatório mensal usa esta ordem:

1. procura `data_purge_monthly_YYYYMM.json`;
2. se existir, usa o consolidado mensal;
3. se não existir, busca `data_purge_metric_YYYYMM_*.json`;
4. calcula os totais mensais;
5. gera `data_purge_monthly_YYYYMM.json`;
6. monta o HTML mensal;
7. publica `send_mail_subject` e `send_mail_body`.

Schedule recomendado no primeiro dia do mês:

```yaml
savings_report_period: monthly
savings_report_month: ""
savings_report_month_mode: previous
savings_consolidate_month: true
savings_prefer_monthly_consolidated: true
savings_delete_raw_after_monthly_consolidation: false
```

Após validação do cliente, pode-se habilitar a limpeza dos brutos:

```yaml
savings_delete_raw_after_monthly_consolidation: true
```

---

## 10. Funcionamento do relatório anual

O relatório anual usa esta ordem:

1. procura `data_purge_yearly_YYYY.json`;
2. se existir, usa o consolidado anual;
3. se não existir, busca `data_purge_monthly_YYYYMM.json`;
4. se faltar mês e o fallback estiver habilitado, busca `data_purge_metric_YYYYMM_*.json`;
5. calcula os totais anuais;
6. gera `data_purge_yearly_YYYY.json`;
7. monta o HTML anual;
8. publica `send_mail_subject` e `send_mail_body`.

Schedule recomendado no início do ano seguinte:

```yaml
savings_report_period: annual
savings_report_year: ""
savings_report_year_mode: previous
savings_consolidate_year: true
savings_prefer_yearly_consolidated: true
savings_annual_fallback_to_raw: true
```

---

## 11. Estrutura de arquivos

| Arquivo                                                      | Descrição                                                  |
| ------------------------------------------------------------ | ---------------------------------------------------------- |
| `purge_manager.yml`                                          | Playbook principal de expurgo.                             |
| `savings_monthly_report.yml`                                 | Playbook de relatório mensal/anual de economia.            |
| `config/purge_manager/purge_matrix.yml`                      | Matriz de ambientes, grupos e hosts.                       |
| `config/purge_manager/apps/*.yml`                            | Arquivos de regras por grupo.                              |
| `roles/data_purge_manager/defaults/main.yml`                 | Variáveis padrão da role.                                  |
| `roles/data_purge_manager/tasks/controller.yml`              | Planejamento, carga de configuração e inventário dinâmico. |
| `roles/data_purge_manager/tasks/linux_purge.yml`             | Execução das regras Linux.                                 |
| `roles/data_purge_manager/tasks/windows_purge.yml`           | Execução das regras Windows.                               |
| `roles/data_purge_manager/tasks/report.yml`                  | Consolidação do relatório, auditoria e métrica JSON.       |
| `roles/data_purge_manager/tasks/80_cifs_upload_files.yml`    | Upload genérico de arquivos para o CIFS.                   |
| `roles/data_purge_manager/tasks/90_build_failure_report.yml` | Relatório de falha operacional.                            |
| `roles/data_purge_manager/templates/report_success.html.j2`  | Template HTML do relatório operacional.                    |
| `roles/data_purge_manager/templates/report_failure.html.j2`  | Template HTML do relatório de falha.                       |
| `roles/data_purge_manager/templates/savings_metric.json.j2`  | Template JSON da métrica por execução.                     |
| `templates/savings_monthly_report.html.j2`                   | Template HTML do relatório mensal/anual.                   |

---

## 12. Execução via CLI

Check:

```bash
ansible-playbook purge_manager.yml \
  -e "motivo=Teste check" \
  -e "purge_applications=sinacor" \
  -e "purge_env=prd" \
  -e "purge_mode=check" \
  -e "purge_confirm_delete=nao"
```

Apply:

```bash
ansible-playbook purge_manager.yml \
  -e "motivo=Expurgo controlado" \
  -e "purge_applications=sinacor" \
  -e "purge_env=prd" \
  -e "purge_mode=apply" \
  -e "purge_confirm_delete=sim"
```

Relatório mensal:

```bash
ansible-playbook savings_monthly_report.yml \
  -e "savings_report_period=monthly" \
  -e "savings_report_month_mode=previous"
```

Relatório anual:

```bash
ansible-playbook savings_monthly_report.yml \
  -e "savings_report_period=annual" \
  -e "savings_report_year_mode=previous"
```
