# Data Purge Manager

Playbook para **gerenciamento de expurgo de dados em servidores Linux e Windows**, com suporte a execução em **modo check/apply**, seleção por **grupo**, **ambiente**, filtro por **hosts do survey**, detecção automática de sistema operacional por **SSH/WinRM**, validações de segurança por `forbidden_paths` e `allowed_prefixes`, remoção controlada de arquivos antigos, remoção opcional de diretórios vazios, relatório HTML consolidado e suporte a engine de execução por regra (`modules` ou `shell`).

A automação:

- lê a matriz de expurgo e os arquivos de configuração dos grupos;
- permite selecionar um ou mais grupos no survey;
- permite selecionar um ou mais ambientes;
- permite filtrar a execução por hosts informados no survey;
- resolve quais hosts pertencem a cada grupo/ambiente;
- detecta automaticamente se cada host é Linux ou Windows;
- executa regras Linux somente em hosts Linux;
- executa regras Windows somente em hosts Windows;
- suporta um mesmo grupo com regras Linux e Windows;
- executa em modo `check`, apenas listando candidatos;
- executa em modo `apply`, removendo arquivos somente com confirmação explícita;
- valida paths perigosos antes de qualquer ação;
- bloqueia paths fora dos prefixos permitidos;
- trata paths ausentes como alerta, sem quebrar toda a execução;
- suporta padrões de inclusão e exclusão de arquivos;
- suporta execução recursiva e remoção opcional de diretórios vazios;
- suporta duas engines de execução por regra: `modules` e `shell`;
- permite usar `modules` para execução mais rastreável e `shell` para regras de alto volume;
- gera relatório HTML consolidado por host e regra;
- publica `send_mail_subject` e `send_mail_body` para o job de envio de e-mail.

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `motivo` | string | Motivo informado pelo operador para rastreabilidade no relatório. |
| `purge_applications` | string/list | Grupos a serem considerados na execução. Pode receber um ou mais valores separados por vírgula. Ex.: `lab_linux,lab_windows`. No relatório aparece como **Grupo(s)**. |
| `purge_env` | string/list | Ambiente ou ambientes a considerar. Ex.: `hml`, `prd` ou `hml,prd`. |
| `survey_hosts` | string/list | Lista opcional de hosts para filtrar o escopo. Quando vazio, usa os hosts definidos na matriz para os grupos/ambientes selecionados. |
| `purge_mode` | string | Modo da automação: `check` ou `apply`. |
| `purge_confirm_delete` | string/bool | Confirmação explícita para remoção real. Para apagar, precisa estar como `sim` junto com `purge_mode=apply`. |
| `purge_include_global_rules` | string/bool | Define se regras globais da matriz devem ser incluídas na execução. |

### Variáveis operacionais importantes

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `purge_config_root` | string | Diretório raiz das configurações. Normalmente `{{ playbook_dir }}/config/purge_manager`. |
| `purge_matrix_file` | string | Caminho do arquivo de matriz. Normalmente `{{ purge_config_root }}/purge_matrix.yml`. |
| `purge_apps_dir` | string | Diretório onde ficam os arquivos de grupos. Normalmente `{{ purge_config_root }}/apps`. |
| `purge_wait_timeout` | int | Timeout, em segundos, usado nos testes de porta SSH/WinRM. |
| `purge_linux_port` | int | Porta usada para detectar e conectar em hosts Linux. Padrão: `22`. |
| `purge_windows_port` | int | Porta usada para detectar e conectar em hosts Windows via WinRM. Padrão: `5985`. |
| `purge_linux_become` | bool | Define se a play Linux deve executar com `become`. |
| `purge_windows_winrm_transport` | string | Transporte WinRM. Normalmente `ntlm`. |
| `purge_windows_winrm_scheme` | string | Esquema WinRM. Normalmente `http` para 5985 ou `https` para 5986. |
| `purge_windows_winrm_server_cert_validation` | string | Validação do certificado WinRM. Em ambientes internos, normalmente `ignore`. |
| `purge_windows_operation_timeout_sec` | int | Timeout de operação WinRM. |
| `purge_windows_read_timeout_sec` | int | Timeout de leitura WinRM. |
| `purge_report_timezone` | string | Timezone usado no relatório. Ex.: `America/Sao_Paulo`. |
| `purge_report_sample_limit` | int | Quantidade máxima de amostras de arquivos exibidas por regra no relatório. |
| `purge_engine_default` | string | Engine padrão para regras sem `engine` explícita. Valores suportados: `modules` e `shell`. Recomendado manter `modules` como padrão e usar `shell` em regras de alto volume. |

### Variáveis de segurança

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `purge_min_path_length_linux` | int | Tamanho mínimo aceito para paths Linux. Ajuda a evitar paths perigosos como `/`. |
| `purge_min_path_length_windows` | int | Tamanho mínimo aceito para paths Windows. Ajuda a evitar paths como `C:\`. |
| `purge_forbidden_paths_linux` | list | Lista de paths Linux proibidos. Ex.: `/`, `/tmp`, `/etc`, `/var`. |
| `purge_forbidden_paths_windows` | list | Lista de paths Windows proibidos. Ex.: `C:\`, `C:\Windows`, `C:\Program Files`. |
| `purge_enforce_allowed_prefixes` | bool | Quando `true`, valida se os paths das regras estão dentro dos prefixos permitidos. |
| `purge_allowed_prefixes_required` | bool | Quando `true`, toda regra precisa possuir `allowed_prefixes`. Recomendado para produção. |
| `purge_fail_on_no_hosts` | bool | Quando `true`, falha se nenhum host alvo for resolvido. |
| `purge_allow_survey_hosts_outside_matrix` | bool | Permite ou bloqueia hosts informados no survey que não estejam na matriz. Recomendado `false` em produção. |
| `purge_global_rules_apply_to_adhoc_hosts` | bool | Controla se hosts fora da matriz podem receber regras globais. Recomendado `false`. |
| `purge_allow_multi_env_apply` | bool | Permite `apply` em múltiplos ambientes ao mesmo tempo. Recomendado `false`. |

---

## 2. Estrutura esperada

- **Entrada simplificada no Survey**: o operador informa `motivo`, `purge_applications`, `purge_env`, `survey_hosts`, `purge_mode`, `purge_confirm_delete` e, quando necessário, `purge_include_global_rules`.
- **Grupo**: representa o escopo funcional da aplicação ou conjunto de paths. Internamente a variável ainda pode aparecer como `applications`, mas no relatório e na operação o conceito é **Grupo**.
- **Ambiente**: representa o escopo operacional, como `hml`, `prd` ou `dr`.
- **Matriz**: define quais hosts pertencem a cada grupo em cada ambiente.
- **Arquivos de grupo**: definem as regras de expurgo, paths, patterns, exclusions, idade dos arquivos e allowed prefixes.
- **Hosts do survey**: funcionam como filtro de escopo. Eles não criam regras sozinhos.
- **Detecção de sistema operacional**: a automação testa SSH e WinRM, monta `linux_targets` e `windows_targets`, e executa cada play no grupo correto.
- **Grupo misto**: o mesmo grupo pode ter regras Linux e Windows. A automação executa `rules.linux` em hosts Linux e `rules.windows` em hosts Windows.
- **Modo Check**: lista os arquivos candidatos, valida paths e gera relatório, sem remover nada.
- **Modo Apply**: remove os arquivos candidatos somente quando `purge_mode=apply` e `purge_confirm_delete=sim`.
- **Proteção por path**: `forbidden_paths` bloqueia paths perigosos e `allowed_prefixes` limita onde cada grupo pode atuar.
- **Relatório consolidado**: exibe status por host e regra, candidatos, removidos, paths ausentes, paths bloqueados e amostras.

---

## 3. YAML de exemplo

### 3.1 Defaults / parâmetros principais

```yaml
purge_config_root: "{{ playbook_dir }}/config/purge_manager"
purge_matrix_file: "{{ purge_config_root }}/purge_matrix.yml"
purge_apps_dir: "{{ purge_config_root }}/apps"

purge_mode: "check"
purge_confirm_delete: "nao"
purge_include_global_rules: "nao"

# Engine padrão de execução.
# modules: usa módulos Ansible, mais rastreável.
# shell: usa find/PowerShell controlado, melhor para alto volume.
purge_engine_default: "modules"

purge_wait_timeout: 3

purge_linux_port: 22
purge_linux_become: true

purge_windows_port: 5985
purge_windows_winrm_transport: "ntlm"
purge_windows_winrm_scheme: "http"
purge_windows_winrm_server_cert_validation: "ignore"
purge_windows_operation_timeout_sec: 60
purge_windows_read_timeout_sec: 90

purge_min_path_length_linux: 4
purge_min_path_length_windows: 6

purge_enforce_allowed_prefixes: true
purge_allowed_prefixes_required: false

purge_fail_on_no_hosts: true
purge_allow_survey_hosts_outside_matrix: false
purge_global_rules_apply_to_adhoc_hosts: false
purge_allow_multi_env_apply: false

purge_report_title: "Data Purge Manager"
purge_report_subject_prefix: "Ansible-Report"
purge_report_timezone: "America/Sao_Paulo"
purge_report_sample_limit: 10
```

### 3.2 Survey para Check Linux e Windows

```yaml
motivo: "Teste check Linux e Windows"
purge_applications: "lab_linux,lab_windows"
purge_env: "prd"
survey_hosts: ""
purge_mode: "check"
purge_confirm_delete: "nao"
purge_include_global_rules: "nao"
```

### 3.3 Survey para Apply Linux

```yaml
motivo: "Teste apply Linux"
purge_applications: "lab_linux"
purge_env: "prd"
survey_hosts: ""
purge_mode: "apply"
purge_confirm_delete: "sim"
purge_include_global_rules: "nao"
```

### 3.4 Survey usando filtro por host

```yaml
motivo: "Teste com host informado no survey"
purge_applications: "lab_linux,lab_windows"
purge_env: "prd"
survey_hosts: "192.168.122.165"
purge_mode: "check"
purge_confirm_delete: "nao"
```

> O `survey_hosts` apenas filtra o escopo. Se o host informado não pertencer ao grupo/ambiente selecionado, ele não deve receber regras.

### 3.5 Survey com múltiplos ambientes em Check

```yaml
motivo: "Teste múltiplos ambientes"
purge_applications: "lab_linux,lab_windows"
purge_env: "hml,prd"
survey_hosts: ""
purge_mode: "check"
purge_confirm_delete: "nao"
```

### 3.6 Matriz de exemplo

```yaml
envs:
  prd:
    groups:
      lab_linux:
        members:
          - 192.168.122.165

      lab_windows:
        members:
          - 192.168.122.224

      sinacor:
        members:
          - 192.168.122.165
          - 192.168.122.224
```

### 3.7 Grupo Linux de exemplo

```yaml
---
name: lab_linux
description: "Grupo de teste Linux"

allowed_prefixes:
  linux:
    - "/opt/purge-lab"

rules:
  linux:
    - name: lab_linux_logs_30d
      description: "Remove logs Linux antigos"
      paths:
        - "/opt/purge-lab/app_linux_a/logs"
      patterns:
        - "*.log"
        - "*.txt"
      exclude_patterns:
        - "keep-*"
      age_days: 30
      recursive: false
      delete_empty_dirs: false
      enabled: true
      engine: modules
```

### 3.8 Regra Linux usando engine shell para alto volume

```yaml
---
name: lab_linux
description: "Grupo de teste Linux"

allowed_prefixes:
  linux:
    - "/opt/purge-lab"

rules:
  linux:
    - name: lab_linux_logs_30d_shell
      description: "Remove logs antigos usando find controlado"
      paths:
        - "/opt/purge-lab/app_linux_a/logs"
      patterns:
        - "*.log"
        - "*.txt"
      exclude_patterns:
        - "keep-*"
      age_days: 30
      recursive: true
      delete_empty_dirs: true
      enabled: true
      engine: shell
```

### 3.9 Grupo misto Linux e Windows

```yaml
---
name: sinacor
description: "Grupo de expurgo do SINACOR"

allowed_prefixes:
  linux:
    - "/opt/sinacor"
    - "/var/log/sinacor"

  windows:
    - "D:\\SINACOR"
    - "E:\\SINACOR"

rules:
  linux:
    - name: sinacor_linux_logs_30d
      description: "Remove logs Linux antigos do SINACOR"
      paths:
        - "/var/log/sinacor"
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
      description: "Remove logs Windows antigos do SINACOR"
      paths:
        - "D:\\SINACOR\\logs"
      patterns:
        - "*.log"
      exclude_patterns:
        - "keep-*"
      age_days: 30
      recursive: true
      delete_empty_dirs: false
      enabled: true
      engine: modules
```

---

## 4. Estrutura de arquivos da automação

| Arquivo | Descrição |
| --- | --- |
| `site.yml` | Playbook principal. Orquestra as fases `controller`, `linux_purge`, `windows_purge` e `report`. |
| `ansible.cfg` | Configurações do Ansible para execução do projeto. |
| `collections/requirements.yml` | Collections necessárias para execução, como `ansible.windows`. |
| `config/purge_manager/purge_matrix.yml` | Matriz de ambientes, grupos, membros e regras globais. |
| `config/purge_manager/apps/*.yml` | Arquivos de configuração dos grupos de expurgo. |
| `roles/data_purge_manager/defaults/main.yml` | Variáveis padrão da role, incluindo segurança, conexão, caminhos de configuração e relatório. |
| `roles/data_purge_manager/tasks/main.yml` | Roteador da role. Executa a fase correta conforme `data_purge_phase`. |
| `roles/data_purge_manager/tasks/controller.yml` | Fase de planejamento. Normaliza entradas, carrega configurações, resolve o plano, valida e cria inventário dinâmico. |
| `roles/data_purge_manager/tasks/00_normalize_inputs.yml` | Normaliza as entradas do survey, transforma strings em listas e calcula `purge_apply_enabled`. |
| `roles/data_purge_manager/tasks/10_load_config.yml` | Valida e carrega a matriz e os arquivos de grupos. |
| `roles/data_purge_manager/tasks/11_load_one_app.yml` | Carrega individualmente cada arquivo de grupo e consolida a configuração final. |
| `roles/data_purge_manager/tasks/20_resolve_plan.yml` | Resolve quais hosts, grupos, ambientes e regras entram na execução. |
| `roles/data_purge_manager/tasks/30_validate_plan.yml` | Valida o plano antes da execução, incluindo grupos inexistentes, ambientes inexistentes, hosts sem regra e segurança do modo apply. |
| `roles/data_purge_manager/tasks/35_create_dynamic_hosts.yml` | Detecta SSH/WinRM, monta `linux_targets`, `windows_targets` e hosts não classificados. |
| `roles/data_purge_manager/tasks/linux_purge.yml` | Executa a fase Linux nos hosts classificados como Linux e direciona cada regra para a engine `modules` ou `shell`. |
| `roles/data_purge_manager/tasks/51_linux_rule_modules.yml` | Executa uma regra Linux usando módulos Ansible como `find` e `file`. Mais rastreável, indicado para volumes menores ou homologação. |
| `roles/data_purge_manager/tasks/52_linux_rule_shell.yml` | Executa uma regra Linux com `find` e shell controlado. Usa fluxo `SCAN -> DELETE -> EMPTY DIRS -> CLEANUP`, indicado para diretórios com muitos arquivos. |
| `roles/data_purge_manager/tasks/windows_purge.yml` | Executa a fase Windows nos hosts classificados como Windows e direciona cada regra para a engine `modules` ou `shell`. |
| `roles/data_purge_manager/tasks/61_windows_rule_modules.yml` | Executa uma regra Windows usando módulos como `win_find`, `win_file` e validações PowerShell controladas. Mais rastreável, indicado para volumes menores ou homologação. |
| `roles/data_purge_manager/tasks/62_windows_rule_shell.yml` | Executa uma regra Windows com PowerShell controlado. Usa fluxo `SCAN -> DELETE -> EMPTY DIRS -> CLEANUP`, indicado para diretórios com muitos arquivos. |
| `roles/data_purge_manager/tasks/report.yml` | Consolida os relatórios por host, calcula métricas e publica `send_mail_subject` e `send_mail_body`. |
| `roles/data_purge_manager/tasks/90_build_failure_report.yml` | Monta relatório de falha quando ocorre erro controlado ou falha crítica no planejamento. |
| `roles/data_purge_manager/templates/report_success.html.j2` | Template HTML do relatório de sucesso/alerta. |
| `roles/data_purge_manager/templates/report_failure.html.j2` | Template HTML do relatório de falha. |

---

## 5. Execução CLI

### 5.1 Check em todos os hosts resolvidos pela matriz

```bash
ansible-playbook site.yml \
  -e "motivo=Teste check" \
  -e "purge_applications=lab_linux,lab_windows" \
  -e "purge_env=prd" \
  -e "purge_mode=check" \
  -e "purge_confirm_delete=nao"
```

### 5.2 Check filtrando por host do survey

```bash
ansible-playbook site.yml \
  -e "motivo=Teste com host" \
  -e "purge_applications=lab_linux,lab_windows" \
  -e "purge_env=prd" \
  -e "survey_hosts=192.168.122.165" \
  -e "purge_mode=check" \
  -e "purge_confirm_delete=nao"
```

### 5.3 Apply Linux

```bash
ansible-playbook site.yml \
  -e "motivo=Apply Linux" \
  -e "purge_applications=lab_linux" \
  -e "purge_env=prd" \
  -e "purge_mode=apply" \
  -e "purge_confirm_delete=sim"
```

### 5.4 Apply Windows

```bash
ansible-playbook site.yml \
  -e "motivo=Apply Windows" \
  -e "purge_applications=lab_windows" \
  -e "purge_env=prd" \
  -e "purge_mode=apply" \
  -e "purge_confirm_delete=sim"
```

### 5.5 Check em múltiplos ambientes

```bash
ansible-playbook site.yml \
  -e "motivo=Check multiambiente" \
  -e "purge_applications=lab_linux,lab_windows" \
  -e "purge_env=hml,prd" \
  -e "purge_mode=check" \
  -e "purge_confirm_delete=nao"
```

---

## 6. Funcionamento do `check`

No modo `check`, a automação:

1. normaliza as variáveis do survey;
2. carrega a matriz e os arquivos de grupos;
3. valida grupos e ambientes selecionados;
4. resolve os hosts alvo;
5. aplica o filtro de `survey_hosts`, quando informado;
6. monta o plano por host;
7. detecta Linux ou Windows por SSH/WinRM;
8. executa as regras compatíveis com o sistema operacional;
9. valida paths permitidos e bloqueados;
10. lista arquivos candidatos conforme `patterns`, `age_days` e `recursive`;
11. aplica `exclude_patterns`;
12. não remove arquivos;
13. gera relatório HTML consolidado.

Exemplo de comportamento esperado:

```text
Modo: Check
Candidatos: 10
Removidos: 0
Falhas: 0
```

---

## 7. Funcionamento do `apply`

No modo `apply`, a automação executa o mesmo fluxo do `check`, mas remove os arquivos candidatos quando as duas condições são verdadeiras:

```yaml
purge_mode: apply
purge_confirm_delete: sim
```

Se apenas `purge_mode=apply` for informado sem confirmação, a remoção não deve ocorrer.

Durante o `apply`, a automação:

- valida os paths antes de remover qualquer arquivo;
- ignora paths bloqueados;
- trata paths ausentes como alerta;
- remove apenas arquivos candidatos filtrados;
- respeita `exclude_patterns`;
- remove diretórios vazios somente quando `delete_empty_dirs=true`;
- registra removidos, falhas e amostras no relatório.

Exemplo de comportamento esperado:

```text
Modo: Apply
Candidatos: 10
Removidos: 10
Falhas: 0
```

---

## 8. Resolução de hosts e regras

A regra mental da automação é:

```text
Grupo + Ambiente definem as regras.
survey_hosts define o recorte dos hosts.
```

### 8.1 Sem `survey_hosts`

Se `survey_hosts` estiver vazio, a automação usa todos os hosts da matriz para os grupos e ambientes selecionados.

Exemplo:

```yaml
purge_applications: "lab_linux,lab_windows"
purge_env: "prd"
survey_hosts: ""
```

Resultado esperado:

```yaml
target_hosts:
  - 192.168.122.165
  - 192.168.122.224
```

### 8.2 Com `survey_hosts`

Se `survey_hosts` for informado, ele filtra o escopo.

Exemplo:

```yaml
purge_applications: "lab_linux,lab_windows"
purge_env: "prd"
survey_hosts: "192.168.122.165"
```

Resultado esperado:

```text
Somente o host 192.168.122.165 entra na execução.
Ele recebe apenas regras dos grupos aos quais pertence na matriz.
```

### 8.3 Host fora da matriz

Por segurança, em produção recomenda-se:

```yaml
purge_allow_survey_hosts_outside_matrix: false
```

Assim, se o operador passar um host fora da matriz, ele não recebe regras e não executa expurgo.

---

## 9. Detecção Linux/Windows

A automação detecta o sistema operacional por teste de porta:

- SSH na porta `22` para Linux;
- WinRM na porta `5985` para Windows.

O fluxo é:

1. testa SSH em todos os hosts alvo;
2. testa WinRM em todos os hosts alvo;
3. monta uma lista bruta de Linux;
4. monta uma lista de Windows;
5. remove da lista Linux qualquer host que respondeu WinRM;
6. cria `linux_targets`;
7. cria `windows_targets`;
8. registra hosts inalcançáveis em `purge_unreachable_or_unknown_hosts`.

Exemplo esperado:

```yaml
linux_targets:
  - 192.168.122.165

windows_targets:
  - 192.168.122.224

unreachable_or_unknown: []
```

A regra adotada é:

```text
Se respondeu WinRM, o host é tratado como Windows.
```

---

## 10. Grupo misto Linux e Windows

Um mesmo grupo pode possuir regras Linux e Windows.

Exemplo:

```yaml
purge_applications: "sinacor"
purge_env: "prd"
```

Matriz:

```yaml
envs:
  prd:
    groups:
      sinacor:
        members:
          - 192.168.122.165
          - 192.168.122.224
```

Se `192.168.122.165` for Linux e `192.168.122.224` for Windows, o comportamento será:

```text
192.168.122.165 executa somente rules.linux do grupo sinacor.
192.168.122.224 executa somente rules.windows do grupo sinacor.
```

---

## 11. Segurança de paths

Antes de listar ou remover arquivos, a automação valida os paths das regras.

### 11.1 Forbidden paths

Paths perigosos são bloqueados por segurança.

Exemplo Linux:

```yaml
purge_forbidden_paths_linux:
  - "/"
  - "/tmp"
  - "/etc"
  - "/var"
```

Exemplo Windows:

```yaml
purge_forbidden_paths_windows:
  - "C:\\"
  - "C:\\Windows"
  - "C:\\Program Files"
```

### 11.2 Allowed prefixes

Os `allowed_prefixes` limitam onde cada grupo pode atuar.

Exemplo:

```yaml
allowed_prefixes:
  linux:
    - "/opt/purge-lab"
```

Este path passa:

```text
/opt/purge-lab/app_linux_a/logs
```

Este path bloqueia:

```text
/tmp/purge-lab-blocked
```

Em produção, recomenda-se:

```yaml
purge_enforce_allowed_prefixes: true
purge_allowed_prefixes_required: true
```

---

## 12. Regras de expurgo

Cada regra define quais arquivos serão considerados candidatos.

| Campo | Descrição |
| --- | --- |
| `name` | Nome único da regra. |
| `description` | Descrição exibida no relatório. |
| `paths` | Diretórios avaliados pela regra. |
| `patterns` | Padrões de arquivos incluídos. Ex.: `*.log`, `*.tmp`, `*.csv`. |
| `exclude_patterns` | Padrões excluídos da remoção. Ex.: `keep-*`. |
| `age_days` | Idade mínima do arquivo, em dias. |
| `recursive` | Define se a busca será recursiva. |
| `delete_empty_dirs` | Define se diretórios vazios serão removidos após o expurgo. |
| `enabled` | Habilita ou desabilita a regra. |
| `engine` | Motor de execução da regra. Valores suportados: `modules` e `shell`. Quando ausente, usa `purge_engine_default`. |

---


### 12.1 Engines de execução

Cada regra pode usar uma das engines abaixo:

| Engine | Como funciona | Quando usar |
| --- | --- | --- |
| `modules` | Usa módulos Ansible (`find`, `file`, `win_find`, `win_file`) para buscar candidatos e remover arquivos. | Padrão recomendado, mais rastreável e simples para volumes pequenos ou médios. |
| `shell` | Usa shell/PowerShell controlado no host remoto. O fluxo é separado em `SCAN`, `DELETE`, `EMPTY DIRS` e `CLEANUP`. | Regras de alto volume, diretórios recursivos grandes ou expurgos com muitos arquivos. |

A engine `shell` **não permite comando livre vindo do survey ou do arquivo de grupo**. A regra continua declarativa e aceita apenas campos como `paths`, `patterns`, `exclude_patterns`, `age_days`, `recursive` e `delete_empty_dirs`. A automação monta internamente os comandos controlados.

Fluxo da engine `shell`:

```text
SCAN       -> localiza candidatos e grava lista temporária no host remoto
DELETE     -> remove candidatos somente em modo apply confirmado
EMPTY DIRS -> remove diretórios vazios somente quando habilitado
CLEANUP    -> remove arquivos temporários da execução
```

Recomendação operacional:

```yaml
purge_engine_default: "modules"
```

Use `engine: shell` apenas nas regras em que houver necessidade de performance, por exemplo diretórios com milhares de arquivos ou execução recursiva pesada.

## 13. Saída / Relatório

O relatório HTML contém:

- cabeçalho com modo, job, executor, data, grupos e ambientes;
- cards com total de hosts, regras, candidatos, removidos, alertas e bloqueios;
- avisos de planejamento, como hosts não classificados ou hosts sem regra;
- resumo por host e regra;
- status da regra: `OK`, `Alerta`, `Bloqueado` ou `Falha`;
- critérios usados: idade, recursividade e remoção de diretórios vazios;
- quantidade de paths existentes, ausentes e bloqueados;
- candidatos encontrados;
- removidos em modo `apply`;
- falhas de remoção, quando existirem;
- amostras dos arquivos candidatos;
- observação diferenciando `Check` e `Apply`.

### Artefatos publicados

A automação publica via `set_stats`:

```yaml
send_mail_subject: "Assunto do e-mail"
send_mail_body: "HTML do relatório"
```

Essas variáveis são consumidas pelo job de envio de e-mail.

---

## 14. Job de envio de e-mail

O job responsável pelo envio de e-mail deve consumir as variáveis publicadas pela automação principal:

- `send_mail_subject`
- `send_mail_body`

Comportamento esperado:

- **OK**: execução sem alertas relevantes;
- **Alerta**: paths ausentes, paths bloqueados ou hosts não classificados;
- **Crítico**: falha técnica, erro de planejamento ou falha não tratada.

O e-mail de falha deve informar:

- task afetada;
- módulo/ação;
- mensagem resumida;
- diagnóstico provável;
- orientação de correção;
- contexto da execução.

---

## 15. Testes recomendados

Antes de uso em produção, validar pelo menos os seguintes cenários:

1. `check` Linux;
2. `check` Windows;
3. `check` Linux e Windows juntos;
4. `apply` Linux;
5. `apply` Windows;
6. `apply` sem `purge_confirm_delete=sim`;
7. path ausente;
8. path bloqueado por `allowed_prefixes`;
9. path proibido por `forbidden_paths`;
10. regra com `recursive=false`;
11. regra com `recursive=true`;
12. regra com `delete_empty_dirs=true`;
13. `exclude_patterns` preservando arquivos;
14. execução com `survey_hosts`;
15. host fora da matriz;
16. host inalcançável;
17. múltiplos ambientes em `check`;
18. múltiplos ambientes em `apply` bloqueado;
19. regras com `engine: modules`;
20. regras com `engine: shell`;
21. comparação de candidatos entre `modules` e `shell`;
22. grupo inexistente;
20. ambiente inexistente;
21. idempotência: `check`, `apply`, `check`, `apply` novamente.

---

## 16. Recomendações para produção

Para uso em cliente, recomenda-se:

```yaml
purge_enforce_allowed_prefixes: true
purge_allowed_prefixes_required: true
purge_fail_on_no_hosts: true
purge_allow_survey_hosts_outside_matrix: false
purge_global_rules_apply_to_adhoc_hosts: false
purge_allow_multi_env_apply: false
```

Também é recomendado:

- começar sempre em modo `check`;
- validar o relatório antes de liberar `apply`;
- manter `allowed_prefixes` por grupo;
- evitar paths genéricos demais;
- limitar amostras no relatório com `purge_report_sample_limit`;
- executar `apply` por ambiente em produção;
- manter revisão operacional para novas regras de expurgo;
- manter `purge_engine_default: "modules"`;
- usar `engine: shell` apenas para regras com alto volume de arquivos, após validação em modo `check`.

---

## 17. Observações importantes

### Check nunca remove arquivos

O modo `check` apenas lista candidatos e valida segurança.

### Apply exige confirmação

A remoção real exige:

```yaml
purge_mode: apply
purge_confirm_delete: sim
```

### Survey host não cria regra sozinho

O `survey_hosts` apenas filtra o escopo. As regras continuam vindo da matriz e dos arquivos de grupo.

### O grupo define o escopo funcional

Um grupo pode representar uma aplicação, sistema ou conjunto de paths. Ex.: `sinacor`, `marketdata`, `lab_linux`.

### O sistema operacional decide qual bloco de regra roda

- Host Linux executa `rules.linux`.
- Host Windows executa `rules.windows`.

### Diretórios vazios são tratados com cuidado

A automação não remove diretórios não vazios como consequência de `file state=absent`. A remoção de diretórios vazios é controlada e só ocorre quando `delete_empty_dirs=true`. Na engine `shell`, essa etapa é separada da remoção de arquivos para facilitar auditoria e troubleshooting.

