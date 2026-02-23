# OCP Must Gather

Playbook que realiza **coleta de must-gather em clusters OpenShift**, salvando o bundle em um **share CIFS** e criando um **chamado (case)** no portal da Red Hat para anexar o arquivo — ou apenas anexando o Must Gather em um case existente. A automação suporta seleção de cluster via Survey, seleção opcional de node e geração de **relatório HTML consolidado** (com tempos, parâmetros e informações do case).

---

## 1. Sobre o Workflow

O workflow **WF_Devops_OCP_MustGather** encadeia dois templates:

- **Devops_OCP_MustGather**: Executa o `playbook-must-gather.yml`, responsável por executar a role `must_gather_corp`.
- **Devops_Send_Email**: realiza o envio de e-mail para a equipe com o resultado da execução.

O workflow pode ser executado pontualmente, de forma manual (menu **Templates** → ícone de foguete/Launch) e também via **Schedules**.

---

## 2. Variáveis

| Variável                           | Tipo       | Descrição                                                                                                                                     |
| ---------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ocp_must_gather_cluster`          | string     | Cluster alvo para o must-gather (ex.: `tuti`, `hofix`).                                                                                       |
| `ocp_user`                         | string     | Usuário para login no cluster.                                                                                                                |
| `ocp_password`                     | string     | Senha do usuário para login no cluster.                                                                                                       |
| `ocp_must_gather_node`             | string     | Node que executará o must-gather. Se vazio, a automação escolhe automaticamente um worker Ready/schedulable, excluindo masters/control-plane. |
| `ocp_must_gather_command`          | string     | Comando customizado do must-gather. Se vazio, usa o comando padrão (`oc adm must-gather ...`).                                                |
| `ocp_must_gather_existing_case_id` | string     | Se o case já existir, informar o Case ID para **somente anexar** o must-gather ao case.                                                       |
| `case_description`                 | string     | Descrição do case (quando o case é criado pela automação).                                                                                    |
| `case_summary`                     | string     | Título do case (quando o case é criado pela automação).                                                                                       |
| `case_severity`                    | string/int | Severidade do case (ex.: `4` (Low), `3` (Normal)).                                                                                            |
| `openshift_version`                | string     | Versão do OpenShift (aparece no case, quando criado).                                                                                         |
| `case_type`                        | string     | Tipo do case (ex.: `Customer Service`, `Other`, `Configuration`).                                                                             |
| `motivo`                           | string     | Informação livre para identificação da execução no relatório.                                                                                 |
| `ocp_must_gather_cifs_path`        | string     | Share CIFS (ex.: `//AG-MZ-IW-FS-002.../must-gather`).                                                                                         |
| `ocp_must_gather_cifs_mount_dir`   | string     | Diretório local de montagem (ex.: `/mnt/must-gather`).                                                                                        |
| `offline_token`                    | string     | Offline token usado para gerar access token e criar case via API.                                                                             |
| `rh_portal_user`                   | string     | Usuário do portal Red Hat (também usado como diretório remoto no SFTP).                                                                       |
| `ocp_must_gather_case_token`       | string     | Token do SFTP usado como “senha” no `sshpass` durante o upload.                                                                               |
| `ocp_must_gather_proxy`            | string     | Proxy usado no `ProxyCommand nc` (quando aplicável).                                                                                          |
| `ocp_must_gather_proxy_auth`       | string     | Credenciais do proxy no formato `user:pass` (quando aplicável).                                                                               |

---

## 3. Estrutura esperada

Os arquivos estão distribuídos no formato de role:

- `site.yml` — playbook principal
- `roles/must_gather_corp/`
  - `tasks/` — Execução (cluster, node, storage, coleta, upload, limpeza, report)
  - `templates/` — Template(s) (ex.: `report.html.j2`, quando aplicável)
  - `defaults/main.yml` — Definições de clusters, CIFS e parâmetros padrão

---

## 4. Tokens e links importantes

### 4.1 Offline Token (para criar case via API)

- Gerar offline token: https://access.redhat.com/management/api
- Artigo explicando offline token e expiração (30 dias sem uso): https://access.redhat.com/articles/3626371

A automação utiliza o offline token para gerar um **refresh/access token** e conseguir usar a API para criação de case.

### 4.2 Token de SFTP (para upload do must-gather)

- Artigo sobre upload via SFTP: https://access.redhat.com/articles/5594481
- Gerar token do SFTP: https://access.redhat.com/sftp-token/#/login

---

## 5. YAML de exemplo

### 5.1 Variáveis de execução (exemplo)

```yaml
ocp_must_gather_cluster: "tuti"
ocp_user: "admin"
ocp_password: "********"

ocp_must_gather_node: "" # vazio = seleção automática
ocp_must_gather_command: "" # vazio = comando padrão
ocp_must_gather_existing_case_id: "" # vazio = cria case

case_summary: "OCP Must-Gather - Cluster TUTI"
case_description: "Coleta de must-gather para análise do suporte."
case_severity: 4
openshift_version: "4.16"
case_type: "Configuration"

motivo: "Coleta solicitada pela Operação"

ocp_must_gather_cifs_path: "//AG-MZ-IW-FS-002.corp.bradesco.com.br/Apps/Ansible/must-gather"
ocp_must_gather_cifs_mount_dir: "/mnt/must-gather"

rh_portal_user: "seu.usuario"
ocp_must_gather_case_token: "TOKEN_SFTP_AQUI"

ocp_must_gather_proxy: "proxy.exemplo.local:8080"
ocp_must_gather_proxy_auth: "user:pass"
```

### 5.2 Comando customizado (exemplo)

```yaml
ocp_must_gather_command: >-
  oc adm must-gather --image=registry.redhat.io/openshift4/ose-must-gather-rhel8
```

---

## 6. Execução (CLI)

```bash
ansible-playbook -i <inventario> site.yml   -e "ocp_must_gather_cluster=tuti"   -e "ocp_user=..." -e "ocp_password=..."   -e "case_summary=..." -e "case_description=..."   -e "case_severity=4" -e "openshift_version=4.x" -e "case_type=Configuration"   -e "rh_portal_user=..."   -e "ocp_must_gather_case_token=..."
```

---

## 7. Saída

- **SUCESSO** – must-gather coletado, compactado e enviado; relatório HTML com informações do case.
- **FALHA** – relatório lista: motivo, task/ação, horários de início/fim, cluster/node (quando disponíveis) e mensagem de erro detalhada.

Artefatos publicados para o job de e-mail:

- `send_mail_subject`
- `send_mail_body`
