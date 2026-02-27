# EDA - DB Log Alert

Solução de monitoração de conectividade com banco de dados (PostgreSQL) utilizando **Event-Driven Ansible (EDA)** no **Ansible Automation Platform (AAP)**.

O fluxo é:

1. Um **script** roda no(s) host(s) monitorado(s), valida a conectividade (`pg_isready` + `SELECT now()`), escreve logs e envia eventos via **HTTP POST** (webhook).
2. O **EDA rulebook** recebe os eventos e, em caso de falha, dispara um **workflow** no Automation Controller.
3. O workflow executa um **Job Template** que gera o **report HTML** (no corpo do e-mail) e publica `send_mail_subject` / `send_mail_body` via `set_stats`.
4. Um **Job Template de e-mail** (já existente no padrão do time) envia o alerta.

---

## 1. Sobre o Workflow

O workflow **WF - DB Log Alert** encadeia dois templates:

- **DB Log Alert** (Job Template): executa o playbook de report/diagnóstico/remediação (set_stats).
- **Send Email** (Job Template): envia o e-mail consumindo `send_mail_subject` / `send_mail_body`.

A execução pode ser disparada automaticamente pelo **EDA Activation** (webhook), e também pode ser executada manualmente no Controller (Launch) para testes.

---

## 2. Componentes

- **Script (host monitorado)**  
  Executa checks no Postgres e publica eventos no webhook do EDA:
  - `db_status=ok` (opcional, controlado por intervalo)
  - `db_status=failed` (com cooldown para evitar spam)

- **Rulebook (EDA)**  
  - Source: `ansible.eda.webhook` (porta 5000)
  - Rules:
    - OK: apenas debug
    - FAIL: dispara workflow no Controller

- **Playbook (Controller JT: DB Log Alert)**  
  - Monta o report base em HTML
  - **Auto-diagnóstico** (quando habilitado) via `delegate_to` no host do DB (ou host alvo de remediação)
  - **Auto-remediação controlada** (quando habilitado) reiniciando serviço remoto via `systemctl`

---

## 3. Variáveis

### 3.1 Variáveis do evento (vindas do script → webhook → rulebook → workflow)

| Variável       | Tipo   | Descrição |
|---|---|---|
| `db_host`      | string | Host alvo (servidor do DB, ou host onde a remediação deve rodar). |
| `db_name`      | string | Nome lógico da base (ex.: `core`, `risk`). |
| `log_file`     | string | Arquivo de log gerado no host monitorado. |
| `error`        | string | Mensagem de erro do check (`psql`/`pg_isready`). |
| `timestamp`    | string | Timestamp do evento (formato livre). |

> Observação: no lab, `db_host` foi usado tanto como “alvo do DB” quanto “alvo da remediação”. Em produção, se necessário, você pode separar `db_host` e `remediation_host`.

### 3.2 Variáveis de controle (definidas no playbook ou no Job Template)

| Variável              | Tipo    | Descrição |
|---|---|---|
| `alert_level`         | string  | Nível de execução: `alert` \| `diagnostics` \| `remediate`. |
| `enable_remediation`  | bool    | Se `true`, permite executar remediação (somente no nível `remediate`). |
| `db_service_name`     | string  | Serviço a reiniciar no host remoto (ex.: `postgresql`, `postgresql-15`, `snmpd`). |
| `ansible_url`         | string  | URL do AAP para gerar link do Job no e-mail. |

---

## 4. Níveis de operação

### 4.1 Alert Only (`alert`)
- Envia e-mail com:
  - Host / Base / Arquivo / Timestamp / Erro
  - Job ID e executor
- **Sem diagnóstico** e **sem remediação**.

### 4.2 Auto-diagnóstico (`diagnostics`)
- Inclui no e-mail um bloco **Diagnóstico (host do DB)** com:
  - `uptime`
  - `df -h`
  - `free -h`
  - `getent hosts <db_host>` (rodando localmente)
  - `systemctl is-active <db_service_name>` (se aplicável)

> O diagnóstico é executado **no host remoto** via `delegate_to: "{{ _db_host }}"` (requer SSH + become quando necessário).

### 4.3 Auto-remediação controlada (`remediate` + `enable_remediation=true`)
- Executa remediação **somente se**:
  - `alert_level == remediate`
  - `enable_remediation == true`
  - `db_service_name` informado
  - erro classificado como “candidato a restart” (ex.: `connection refused`, `timeout`, etc.)
- **Bloqueia automaticamente** remediação para erros de autenticação (ex.: `password authentication failed`).

---

## 5. Estrutura esperada

Sugestão de estrutura no SCM (ex.: Git):

- `rulebooks/db_log_alert.yml` — rulebook do EDA (webhook + rules)
- `playbooks/db_alert_report.yml` — playbook do Job Template (set_stats + diagnóstico/remediação)
- `scripts/pg_check_client.sh` — script do host monitorado
- `scripts/pg_check_simulator_webhook.sh` — simulador (lab/testes)

---

## 6. YAML de exemplo

### 6.1 Rulebook (EDA)

```yaml
- name: Receive DB events via webhook and trigger workflow on failure
  hosts: all

  sources:
    - name: webhook_in
      ansible.eda.webhook:
        host: "0.0.0.0"
        port: 5000

  rules:
    - name: OK - DB connection ok
      condition: event.payload is defined and event.payload.db_status == "ok"
      action:
        debug:
          msg: "Conexão OK | host={{ event.payload.db_host }} db={{ event.payload.db_name }} log={{ event.payload.log_file }}"

    - name: FAIL - DB connection failed -> trigger workflow
      condition: event.payload is defined and event.payload.db_status == "failed"
      actions:
        - debug:
            msg: "Falha detectada | host={{ event.payload.db_host }} db={{ event.payload.db_name }} log={{ event.payload.log_file }} err={{ event.payload.error }}"
        - run_workflow_template:
            name: "WF - DB Log Alert"
            organization: "Default"
            job_args:
              extra_vars:
                db_host: "{{ event.payload.db_host }}"
                db_name: "{{ event.payload.db_name }}"
                log_file: "{{ event.payload.log_file }}"
                error: "{{ event.payload.error }}"
                timestamp: "{{ event.payload.timestamp }}"
```

### 6.2 Playbook (Job Template: DB Log Alert)

Exemplo: controle por vars no playbook (para teste/lab):

```yaml
vars:
  ansible_url: "https://aap-new-aap.apps-crc.testing"
  enable_remediation: true
  alert_level: remediate   # alert | diagnostics | remediate
  db_service_name: snmpd
```

> Em produção, é comum mover `alert_level/enable_remediation/db_service_name` para vars do Job Template (UI) ou para um inventário/grupo.

---

## 7. Script do host (PostgreSQL check + webhook)

O script abaixo:

- Faz `pg_isready` e `psql SELECT now()` com timeout
- Envia `failed` com cooldown (`FAIL_COOLDOWN_SECONDS`)
- Envia `ok` opcional por intervalo (`OK_EVERY_SECONDS`)

```bash
#!/usr/bin/env bash
set -euo pipefail

DB_HOST="10.208.xxx.xxxx"
DB_PORT="5433"
DB_NAME="xxxxxxx"
DB_USERNAME="xxxxxx"
PGPASSWORD="xxxxxxxx"
export PGPASSWORD
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"

SAIDA="/root/logs/$(hostname)_core_$(date '+%Y%m%d').log"

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-http://127.0.0.1:5000}"
OK_EVERY_SECONDS="${OK_EVERY_SECONDS:-60}"
FAIL_COOLDOWN_SECONDS="${FAIL_COOLDOWN_SECONDS:-300}"

_last_fail_sent=0
_last_ok_sent=0

post_eda() {
  local status="$1"
  local error="$2"
  local ts
  ts="$(date '+%d/%m/%Y %H:%M:%S')"
  error="${error//\"/\\\"}"

  curl -sS -X POST "$EDA_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"db_connection\",
      \"db_status\": \"${status}\",
      \"db_name\": \"${DB_NAME}\",
      \"db_host\": \"${DB_HOST}\",
      \"log_file\": \"${SAIDA}\",
      \"error\": \"${error}\",
      \"timestamp\": \"${ts}\"
    }" >/dev/null || true
}

while true; do
  now_epoch="$(date +%s)"
  ts="$(date '+%d/%m/%Y %H:%M:%S')"

  echo "${ts} Starting" >> "$SAIDA"

  set +e
  READY_OUT="$(timeout 5s pg_isready --dbname="$DB_NAME" --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" 2>&1)"
  READY_RC=$?
  set -e
  echo "${ts} ${READY_OUT}" >> "$SAIDA"

  set +e
  SELECT_OUT="$(timeout 8s psql -w -X -qAt --dbname="$DB_NAME" --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" --command='SELECT now();' 2>&1)"
  SELECT_RC=$?
  set -e
  echo "${ts} SELECT: ${SELECT_OUT}" >> "$SAIDA"

  echo "${ts} Done" >> "$SAIDA"

  if [[ "$READY_RC" -ne 0 || "$SELECT_RC" -ne 0 ]]; then
    if (( now_epoch - _last_fail_sent >= FAIL_COOLDOWN_SECONDS )); then
      if [[ "$SELECT_RC" -ne 0 ]]; then
        post_eda "failed" "$SELECT_OUT"
      else
        post_eda "failed" "$READY_OUT"
      fi
      _last_fail_sent=$now_epoch
    fi
  else
    if [[ "$OK_EVERY_SECONDS" -gt 0 ]]; then
      if (( now_epoch - _last_ok_sent >= OK_EVERY_SECONDS )); then
        post_eda "ok" ""
        _last_ok_sent=$now_epoch
      fi
    fi
  fi

  sleep 5
done
```

---

## 8. Execução (Lab CRC / OpenShift Local)

No lab, o webhook do EDA pode ser testado com **port-forward** para o pod da activation:

```bash
oc get pods -n aap | grep activation-job
oc -n aap port-forward pod/<activation-job-...> 5000:5000
```

Em outro terminal (no mesmo host do port-forward):

```bash
EDA_WEBHOOK_URL="http://127.0.0.1:5000" OK_EVERY_SECONDS=10 FAIL_COOLDOWN_SECONDS=60 ./pg_check_client.sh
```

---

## 9. Saída

- **SUCESSO / OK**: logs do EDA mostram “Conexão OK …” (se OK estiver habilitado no script).
- **FALHA**: o EDA dispara o workflow e o e-mail contém:
  - dados do evento
  - diagnóstico inline (quando `alert_level` = `diagnostics` ou `remediate`)
  - remediação (quando `alert_level=remediate` e `enable_remediation=true`)

Artefatos publicados para o job de e-mail:

- `send_mail_subject`
- `send_mail_body`

---

## 10. Troubleshooting

- **Workflow não recebe variáveis**: verifique se o rulebook repassa os campos em `job_args.extra_vars`.
- **Remediação não executa**: requer SSH para `db_host` + `become` para `systemctl`.
- **Warning de limit**: habilite `Prompt on Launch: Limit` no Workflow (opcional, apenas remove warning).
- **Flood de alertas**: aumente `FAIL_COOLDOWN_SECONDS` no script.
