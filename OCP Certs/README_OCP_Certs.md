# OCP Certs (Certificados x Routes)

Playbook/role que faz **validação e (opcionalmente) patch de certificados em Routes do OpenShift**, em ambientes com **milhares de Routes**.

A automação foi otimizada para performance usando **`oc get route -A`** (CLI) em vez de `kubernetes.core.k8s_info`, e o match é feito em lote, comparando **host das Routes** com os **SANs dos certificados (.cer)** encontrados no CIFS.  
O resultado é um **relatório HTML leve**, mostrando apenas as rotas com **MATCH** e avisando quando **não existe rota com MATCH** em algum env/cluster selecionado.

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| motivo | string | Motivo/justificativa da execução (vai para o relatório). |
| check_env | list | Lista de envs/sufixos para checar. Ex.: `['tu','ti','th','fix']`. |
| ocp_user | string | Usuário para login no OpenShift. |
| ocp_password | string | Senha do usuário do OpenShift. |
| cluster_alvo_input | string | Cluster(s) alvo. Ex.: `TUTIHOFIX`, `TUTI`, `HOFIX`, etc. |
| certificate_prefix | string | Prefixo para filtrar certificados no CIFS. Ex.: `troca-modelo-webapp`. |
| mount_cifs | string | Caminho do CIFS (o “path real” que deve aparecer no relatório). Ex.: `//192.168.0.115/certs`. |
| mount_point | string | Diretório onde o CIFS será montado no executor. Ex.: `/opt/ansiblefiles/files/cert-route-validate`. |
| default_domain_filter | string | Domínio/substring para filtrar hosts no CLI (opcional). Ex.: `ocp.lab`. |
| route_action | string | Ação: `report` (somente validação) ou `patch` (aplica mudanças). |
| route_termination | string | TLS termination desejado (ex.: `reencrypt`, `edge`, `passthrough`). |
| route_insecure_policy | string | insecurePolicy desejado (ex.: `Redirect`, `Allow`, `None`). |
| apply_tls_bundle | bool | Se `true` e `route_action=patch`, aplica também cert/key/ca nas Routes com MATCH. |
| use_route_cache | bool | Se `true`, usa cache de blobs de certificado (`cert_blobs`) para acelerar patches repetidos. |
| send_mail | bool | Se `true`, envia e-mail com o HTML do report. |
| mail_to | string | Destinatário(s) do e-mail. |
| mail_subject | string | Assunto do e-mail. |
| mail_from | string | Remetente (opcional, depende do módulo/mail relay). |

---

## 2. Como a automação funciona

### 2.1 Inventário de certificados (CIFS)
1. Monta o CIFS no `mount_point`.
2. Busca arquivos `.cer` pelo `certificate_prefix`.
3. Lê o certificado e extrai **SANs**.
4. Cria uma lista de padrões (`cert_patterns_eff`) que serão usados no match.

### 2.2 Coleta de Routes (rápido)
Em vez de usar `kubernetes.core.k8s_info`, a automação usa:

- `oc get route -A -o custom-columns=... --no-headers`
- Filtra no próprio shell por **domínio** (`grep -F`) e por **env selecionado** (`grep -E`)

Isso reduz o volume antes de virar lista no Ansible e melhora MUITO a performance em clusters com milhares de objetos.

### 2.3 Normalização com campo `env`
O `env` é calculado a partir do host da Route quando existe `'.apps.'`.

Exemplo:
- Host: `troca-modelo-webapp-01.apps.fix.ocp.lab`
- Env: `fix`

### 2.4 Match (host da Route x SAN)
O match é feito em lote:

- Para cada Route, verifica se o `host` bate com algum padrão derivado das SANs.
- Se existir mais de um match possível, escolhe o **mais específico** (maior SAN / maior comprimento).

O match **não usa nome da Route**. Ele usa:
- `route.host` ✅  
versus  
- `cert SANs` ✅

### 2.5 Patch (somente para MATCH)
Se `route_action=patch`, a automação aplica patch apenas nas rotas com `matched=true`.

Patches possíveis:
- `termination`
- `insecurePolicy`
- (opcional) `cert/key/ca` se `apply_tls_bundle=true`

Para não ficar caro em milhares de rotas, o playbook usa:
- `cert_blobs`: carrega cert/key/ca uma vez
- `patched_map`: registra patch por rota com chave `cluster|namespace|name`

### 2.6 Relatório HTML (leve)
O relatório mostra:
- Parâmetros de execução (motivo, clusters, envs, prefixo, ação, termination/insecure, domínio)
- Certificados encontrados no CIFS (com caminho amigável `mount_cifs/arquivo.cer`)
- Apenas rotas com **MATCH** (verde)
- Mensagens simples quando **não existe rota com MATCH** em algum env/cluster selecionado

---

## 3. YAML de exemplo

```yaml
motivo: "Troca de certificados - aplicação troca-modelo"
cluster_alvo_input: "TUTIHOFIX"

check_env:
  - tu
  - ti
  - th
  - fix

ocp_user: kubeadmin
ocp_password: "Senha123"

certificate_prefix: "troca-modelo-webapp"

mount_cifs: "//192.168.0.115/certs"
mount_point: "/opt/ansiblefiles/files/cert-route-validate"

default_domain_filter: "ocp.lab"

route_action: "report"
route_termination: "reencrypt"
route_insecure_policy: "Redirect"

apply_tls_bundle: false
use_route_cache: true

send_mail: true
mail_to: "time@empresa.com"
mail_subject: "[OCP] Certificados x Routes"
```

---

## 4. Execução CLI

```bash
ansible-playbook -i localhost, \
  -e "cluster_alvo_input=TUTIHOFIX" \
  -e "ocp_user=kubeadmin" \
  -e "ocp_password=Senha123" \
  -e "certificate_prefix=troca-modelo-webapp" \
  -e "default_domain_filter=ocp.lab" \
  -e "route_action=report" \
  site.yml
```

> No AAP (Automation Controller), as variáveis são preenchidas pelo Survey do template.

---

## 5. Saída / Interpretação do relatório

- **MATCH (verde)**: Route cujo `host` bate com SAN do certificado.
- **Patch (ALTERADO/SEM MUDANÇA)**: aparece apenas quando `route_action=patch`.
- **Aviso “Não existe rota ...”**: significa que **não existe rota com MATCH** naquele env/cluster selecionado.

---

## 6. Observações importantes

### 6.1 Match é por `host`, não por path
Se existirem duas Routes com o mesmo host (ex.: “/1” e “/2”), ambas podem dar MATCH, porque o certificado é ligado ao host/FQDN.

### 6.2 Performance
O ganho de performance vem de:
- usar `oc get route -A` (CLI) no lugar de `k8s_info`
- filtrar no shell antes de virar lista no Ansible
- match em lote em um único `set_fact` (sem `include_tasks` por rota)
- cache de blobs de certificado

---

## 7. Troubleshooting (erros comuns)

- **`--token: command not found`**  
  O comando `oc ... | grep ...` foi quebrado em várias linhas e o shell interpretou cada linha como comando.  
  Solução: manter o `shell:` em uma linha e/ou usar `set -o pipefail`.

- **`dict object has no attribute item`**  
  Em `register` de loops, `item` nem sempre existe.  
  Solução: extrair `cluster` usando fallback via `ansible_loop_var`.

- **`loop is not a valid attribute for a Block`**  
  Loop só pode ser usado em task, nunca em `block`.

- **Email pesado**  
  O template foi ajustado para mostrar apenas MATCH. Se ficar grande, reduza colunas ou limite o escopo com `default_domain_filter`.

---

## 8. Estrutura (referência)

Exemplo de organização típica:

```
OCP Certs/
├─ defaults/
│  └─ main.yml
├─ tasks/
│  ├─ collect_routes.yml
│  ├─ match_and_apply.yml
│  └─ ...
└─ templates/
   └─ report.html.j2
```
