# F5 Certificates Automation

Playbook para **inventário, rotação e validação automática de certificados no F5 BIG-IP**, com suporte a execução em **modo list/check/apply**, descoberta automática de **certificado atual**, **Client SSL Profiles** impactados, **Virtual Servers / VIPs** relacionados e validação **TLS + HTTP** com base nas **SANs do certificado novo**.

A automação foi simplificada para uso operacional: no modo `apply`, o operador informa apenas o **modo**, o **escopo** (`prd`, `dr` ou ambos), o **prefixo do certificado no CIFS** e o **path de validação**. A partir disso, a automação:

- localiza a pasta correta no CIFS,
- processa o certificado novo,
- identifica o certificado atualmente em uso no F5,
- descobre todos os profiles que usam esse certificado,
- descobre automaticamente os VIPs / targets de validação,
- aplica a troca em todos os profiles do grupo,
- executa a validação TLS + HTTP ao final do grupo,
- gera relatório HTML consolidado.

> Observação: a automação publica `send_mail_subject` e `send_mail_body` via `set_stats` para uso por job separado de envio de e-mail, seguindo o mesmo padrão do modelo de README enviado. fileciteturn4file0

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `f5_certs_mode` | string | Modo da automação: `list`, `check` ou `apply`. |
| `f5_target_scope` | string | Escopo dos sites F5 a considerar: `prd`, `dr` ou `prd,dr`. |
| `certificate_prefix` | string | Prefixo do(s) certificado(s) no CIFS. Pode receber **um ou mais valores separados por vírgula**. Ex.: `agorascan.lab,portal-cert.lab,api-cert.lab`. |
| `single_validate_path` | string | Path HTTP usado na validação pós-troca. Ex.: `/` ou `/health`. |

### Variáveis operacionais importantes (defaults)

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `f5_warning_days` | int | Janela de alerta para certificados próximos do vencimento. |
| `f5_critical_days` | int | Janela crítica de vencimento. |
| `f5_duplicate_delete_grace_days` | int | Quantos dias após a expiração um duplicado pode virar candidato à remoção. |
| `f5_enable_duplicate_cleanup` | bool | Se `true`, permite limpeza automática de duplicados no modo `check`. |
| `f5_duplicate_cleanup_only_if_not_in_use` | bool | Se `true`, não remove duplicado ainda referenciado por profile/chain. |
| `f5_cleanup_delete_key` | bool | Se `true`, remove também a key associada ao certificado deletado. |
| `f5_min_valid_days_after_install` | int | Mínimo de dias de validade exigido para o certificado novo antes do `apply`. |
| `f5_enable_chain_import` | bool | Se `true`, importa a chain no F5. |
| `f5_enable_chain_on_profile` | bool | Se `true`, associa a chain ao Client SSL Profile. |
| `f5_enable_post_handshake_validation` | bool | Se `true`, executa validação TLS após a troca. |
| `f5_enable_post_http_validation` | bool | Se `true`, executa validação HTTP após a troca. |
| `f5_validate_path_default` | string | Path default usado na validação quando não informado. |
| `f5_validate_ok_codes_default` | list[int] | Lista default de códigos HTTP considerados válidos. Normalmente `[200]`. |
| `f5_timewarp_days` | int | Ajuste de data usado em laboratório/simulação. Em produção, manter `0`. |

---

## 2. Estrutura esperada

- **Entrada simplificada no Survey**: no fluxo atual, o operador informa somente `f5_certs_mode`, `f5_target_scope`, `certificate_prefix` e `single_validate_path`.
- **Suporte a múltiplos certificados**: `certificate_prefix` aceita múltiplos valores separados por vírgula; a automação monta um `f5_rotation_plan` interno automaticamente.
- **Fonte dos certificados novos**: o CIFS deve conter uma pasta por certificado, contendo o leaf cert (`.cer/.crt/.pem`), a key (`.key`) e opcionalmente a chain (`CADEIA*.TXT` ou `*chain*`).
- **Descoberta automática**: a automação não depende mais de `profile_name`, `target`, `sni` ou `rotation_plan_yaml` fornecidos pelo usuário.
- **Match do certificado atual**: o certificado atual em uso no F5 é descoberto a partir das **SANs** do certificado novo processado no CIFS.
- **Expansão do grupo**: uma vez identificado o certificado atual, a automação troca **todos os Client SSL Profiles** que usam esse mesmo certificado no site.
- **Descoberta de VIP / target**: a automação usa o índice de Virtual Servers para descobrir automaticamente `target` (`IP:PORT`) para validação.
- **Validação sem dependência de DNS externo**: a validação TLS/HTTP usa o `target` descoberto e a SNI das SANs do certificado novo; quando há `curl`, a automação usa `--resolve`, evitando depender de DNS real do ambiente.
- **Validação ao final do grupo**: a validação é executada **após a troca de todos os profiles do grupo**, evitando falsos `FAIL` em cenários de certificado compartilhado / multi-SAN.
- **Cleanup de duplicados**: no modo `check`, duplicados expirados podem ser limpos automaticamente, com o relatório refletindo o estado pós-cleanup da mesma execução.
- **Relatório consolidado**: o HTML final inclui resumo do `apply`, inventário por site, duplicidade e resultado da limpeza executada.

---

## 3. YAML de exemplo

### 3.1 Defaults / parâmetros principais

```yaml
f5_certs_mode: "check"
f5_target_scope: "prd"
certificate_prefix: ""

f5_sites:
  - name: "prd"
    server: "192.168.141.10"
    port: 443
  - name: "dr"
    server: "192.168.150.10"
    port: 443

f5_warning_days: 30
f5_critical_days: 7
f5_duplicate_delete_grace_days: 10
f5_enable_duplicate_cleanup: false
f5_duplicate_cleanup_only_if_not_in_use: true
f5_cleanup_delete_key: false

mount_cifs: ""
mount_path: "/opt/ansiblefiles/files/f5-certs"

f5_min_valid_days_after_install: 25
f5_enable_post_handshake_validation: true
f5_enable_post_http_validation: true
f5_validate_path_default: "/"
f5_validate_ok_codes_default: [200]

f5_enable_chain_import: false
f5_enable_chain_on_profile: false
f5_timewarp_days: 0
```

### 3.2 Survey simplificado (exemplo)

```yaml
f5_certs_mode: apply
f5_target_scope: prd,dr
certificate_prefix: agorascan.lab,portal-cert.lab,api-cert.lab
single_validate_path: /
```

### 3.3 Exemplo de item interno montado automaticamente

```yaml
f5_rotation_plan:
  - certificate_prefix: agorascan.lab
    validate_path: /
    validate_ok_codes: [200]

  - certificate_prefix: portal-cert.lab
    validate_path: /
    validate_ok_codes: [200]
```

> Esse plano é montado automaticamente pelo playbook a partir do `certificate_prefix`, sem necessidade de `rotation_plan_yaml` manual.

---

## 4. Estrutura de arquivos da automação

### Playbook de entrada

- `f5_certs_playbook.yml`

### Defaults

- `f5_certs_manager/defaults/main.yml`

### Tasks principais

- `00_f5_collect_certs.yml` — coleta certificados instalados e enriquece com `full_path`, `expiration_epoch`, `days_left`, `san`, `san_list_norm`.
- `10_f5_collect_profiles.yml` — coleta Client SSL Profiles.
- `11_map_profile_usage.yml` — monta índices reversos de uso de certificado/chain por profile.
- `12_build_virtual_profile_index.yml` — coleta Virtual Servers e monta índice `profile -> [virtual, pool, target]`.
- `13_build_virtual_cache_for_site.yml` — cache de virtuals por site.
- `14_build_clientssl_cache_for_site.yml` — cache de Client SSL Profiles por site.
- `15_build_cert_cache_for_site.yml` — cache de certificados instalados por site para o `apply` automático.
- `20_process_findings.yml` — classifica inventário em `expired`, `critical`, `warning`, `ok` e detecta duplicidade.
- `30_source_collect_from_cifs.yml` — monta CIFS, busca as pastas de certificados e prepara o inventário de fonte.
- `31_source_process_cert_dir.yml` — processa cada pasta do CIFS, extrai SANs, validade, cert/key match e chain.
- `40_apply_rotation.yml` — prepara caches e executa a rotação por item.
- `41_apply_one_rotation.yml` — resolve a pasta do CIFS e o certificado novo a aplicar.
- `41_apply_one_rotation__per_site.yml` — descobre o certificado atual no site, os profiles impactados e os targets de validação.
- `41_apply_one_rotation__per_site_profile.yml` — troca de fato o Client SSL Profile no F5.
- `42_validate_handshake.yml` — valida TLS + HTTP ao final do grupo.
- `50_cleanup_duplicates.yml` — prepara a limpeza de duplicados candidatos.
- `51_cleanup_one_duplicate.yml` — executa a remoção de um duplicado específico.
- `60_build_report.yml` — monta o relatório HTML final.
- `90_collect_one_site.yml` — coleta inventário por site para o report e reflete o estado pós-cleanup na mesma execução.

---

## 5. Execução (CLI)

```bash
# Inventário / Check
ansible-playbook -i localhost, f5_certs_playbook.yml \
  -e "f5_certs_mode=check" \
  -e "f5_target_scope=prd,dr" \
  -e "certificate_prefix=agorascan.lab" \
  -e "single_validate_path=/"

# Apply de um certificado
ansible-playbook -i localhost, f5_certs_playbook.yml \
  -e "f5_certs_mode=apply" \
  -e "f5_target_scope=prd" \
  -e "certificate_prefix=portal-cert.lab" \
  -e "single_validate_path=/health"

# Apply de múltiplos certificados
ansible-playbook -i localhost, f5_certs_playbook.yml \
  -e "f5_certs_mode=apply" \
  -e "f5_target_scope=prd,dr" \
  -e "certificate_prefix=agorascan.lab,portal-cert.lab,api-cert.lab" \
  -e "single_validate_path=/"
```

> No AAP/AWX, essas variáveis são preenchidas pelo Survey do template; a automação publica o assunto e corpo do e-mail para uso por job separado.

---

## 6. Funcionamento do `apply`

### 6.1 Resolução do certificado novo

Para cada prefixo informado em `certificate_prefix`:

1. a automação procura uma pasta no CIFS que comece com esse prefixo;
2. falha se não encontrar nenhuma pasta;
3. falha se encontrar mais de uma pasta e o prefixo estiver ambíguo;
4. processa o certificado encontrado no `source_cert_inventory`.

### 6.2 Pré-check do certificado novo

Antes de aplicar a troca, a automação valida:

- o certificado tem pelo menos `f5_min_valid_days_after_install` dias de validade;
- a key existe na pasta;
- o cert e a key conferem;
- o certificado possui SANs válidas para descoberta/validação.

### 6.3 Descoberta do certificado atual no F5

No site (`prd` / `dr`) a automação:

1. monta a lista de certificados atualmente em uso por Client SSL Profiles;
2. compara o certificado novo com os certificados instalados no F5 usando as SANs;
3. tenta descobrir o certificado atual nesta ordem:
   - match exato do conjunto de SANs,
   - match por `primary_san`,
   - match por interseção de SANs.

Se mais de um candidato aparecer na mesma etapa, a automação falha por ambiguidade.

### 6.4 Expansão dos profiles impactados

Uma vez identificado o certificado atual compartilhado, a automação procura todos os Client SSL Profiles que usam esse certificado e inclui todos no grupo de troca daquele site.

### 6.5 Descoberta dos targets de validação

Após descobrir os profiles alvo, a automação usa o índice de virtuals para descobrir automaticamente:

- Virtual Server
- Pool
- Target (`IP:PORT`)

### 6.6 Execução da troca

Para cada profile alvo:

- lê o estado atual do `certKeyChain`;
- falha se o profile tiver mais de uma entrada em `certKeyChain` (proteção contra cenário SNI múltiplo);
- importa o certificado novo no F5;
- importa a key nova;
- importa a chain, se habilitado;
- atualiza o Client SSL Profile;
- salva a running-config.

### 6.7 Validação TLS + HTTP

Ao final do grupo, a automação valida:

- **TLS**: compara o `enddate` visto no handshake com a validade esperada do certificado novo;
- **HTTP**: valida o status code retornado pelo path informado.

A validação usa:

- `target` descoberto automaticamente;
- SNI baseada nas SANs do certificado novo;
- `single_validate_path` como path;
- `[200]` como código esperado padrão.

> A validação não depende de DNS externo. Quando há `curl`, a automação usa `--resolve`, forçando o hostname a apontar para o IP do target descoberto.

---

## 7. Funcionamento do `check`

No modo `check`, a automação:

- inventaria certificados instalados por site;
- cruza uso por profile e chain;
- classifica certificados em `expired`, `critical`, `warning` e `ok`;
- detecta duplicidade por SAN / Subject;
- opcionalmente executa limpeza automática de duplicados expirados;
- recalcula o relatório para refletir o estado pós-cleanup da mesma execução.

### Regras de duplicidade

- certificados são agrupados por `SAN` e, se necessário, por `Subject`;
- o item mais antigo do grupo é usado como referência para o status da duplicidade;
- se o mais antigo estiver expirado há pelo menos `f5_duplicate_delete_grace_days`, ele vira **candidato**;
- se `f5_duplicate_cleanup_only_if_not_in_use=true`, a automação não remove certificados ainda em uso.

---

## 8. Saída / Relatório

### APPLY

O relatório HTML contém uma seção por grupo de rotação com:

- site / F5 alvo;
- origem da descoberta;
- certificado atual compartilhado;
- profiles alterados;
- pasta do CIFS usada;
- DNS SANs do certificado novo;
- before / after do cert/key/chain;
- virtuals / pools / targets;
- validação TLS + HTTP consolidada.

### CHECK / LIST

O relatório contém por site:

- cards com contagem de `expired`, `critical`, `warning`, `ok` e `duplicates`;
- tabela de expirados;
- tabela de críticos;
- tabela de warning;
- tabela de duplicidade;
- bloco de limpeza de duplicados executada.

### Artefatos publicados

- `send_mail_subject`
- `send_mail_body`

---

## 9. Observações operacionais

- O fluxo atual **não depende mais de profile manual no survey**.
- O fluxo atual **não depende mais de target manual no survey**.
- O `certificate_prefix` precisa ser suficientemente específico para achar apenas uma pasta no CIFS.
- Em caso de certificados compartilhados / multi-SAN, a validação só ocorre ao final do grupo, evitando falsos negativos.
- Profiles com mais de uma entrada em `certKeyChain` são bloqueados por segurança.
- O uso de `f5_timewarp_days` deve ser restrito a laboratório/simulação.

---

## 10. Convenções recomendadas

- Usar nomes de pasta no CIFS coerentes com o domínio / aplicação.
- Manter os certificados do CIFS com SANs corretas e compatíveis com o ambiente real.
- Preferir SANs DNS válidas para descoberta e validação.
- Usar `certificate_prefix` com nomes únicos, evitando ambiguidade entre pastas.

---

## 11. Exemplo prático de fluxo

### Entrada no survey

```yaml
f5_certs_mode: apply
f5_target_scope: prd
certificate_prefix: troca-modelo-webapp-npci.lab
single_validate_path: /
```

### O que a automação faz

1. encontra a pasta correspondente no CIFS;
2. processa o cert novo;
3. extrai as SANs do cert novo;
4. descobre o certificado atual equivalente no F5;
5. descobre todos os Client SSL Profiles que usam esse certificado atual;
6. descobre o VIP / target pelo Virtual Server;
7. troca todos os profiles do grupo;
8. valida TLS + HTTP com base nas SANs do cert novo;
9. publica o relatório HTML.

