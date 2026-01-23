# IIS Manager (Windows)

Playbook que realiza **gerenciamento de IIS em hosts Windows** (Application Pools e serviços principais), com suporte a **start / stop / restart / info** e geração de **relatório HTML** para envio por e-mail.

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| survey_hosts | string | Lista de hosts Windows (separados por vírgula). Ex.: `srv01,srv02` |
| motivo | string | Motivo/justificativa da execução (aparece no e-mail). Default: `N/D` |
| iis_manage_pools | string\|bool | Habilita o bloco de Application Pools. Aceita `sim/nao` (ou `true/false`). Default: `sim` |
| iis_pool_operation | string | Operação nos Pools: `start`, `stop`, `restart`, `info`. Default: `start` |
| iis_pools | string | Lista de pools (separados por vírgula). **Vazio = todos**. Ex.: `PoolA,PoolB` |
| iis_pool_max_retries | int | Tentativas (retries) por pool. Default: `3` |
| iis_manage_service | string\|bool | Habilita o bloco de serviços IIS. Aceita `sim/nao` (ou `true/false`). Default: `nao` |
| iis_service_operation | string | Operação nos serviços: `start`, `stop`, `restart`, `info`. Default: `restart` |
| iis_service_max_retries | int | Tentativas (retries) por serviço. Default: `3` |

### Serviços gerenciados (sem survey)

Para facilitar o uso, a automação trabalha com a lista de serviços principais do IIS (sem o usuário precisar informar):

- `WAS`
- `W3SVC`
- `IISADMIN`

> Observação: em alguns ambientes `IISADMIN` pode não existir. Nesse caso, o relatório marca como **ausente**, sem quebrar a execução.

---

## 2. Como funciona

1. **Valida** `survey_hosts` (não pode ser vazio).
2. **Normaliza** entradas do survey (ex.: `sim/nao` → boolean).
3. **Cria inventário dinâmico** (hosts Windows alcançáveis via WinRM).
4. Executa nos `windows_targets`:
   - **Application Pools**
     - `start/stop/restart`: aplica somente no que precisa (evita ação desnecessária).
     - `info`: apenas consulta e retorna estado atual.
     - `iis_pools` vazio ⇒ seleciona **todos** os pools existentes no host.
   - **Serviços IIS**
     - `start/stop/restart`: aplica com retries.
     - `info`: consulta informações do serviço (sem alterar estado).
5. Consolida resultados e gera **HTML** para o e-mail, incluindo:
   - hosts inalcançáveis,
   - hosts com erro de execução,
   - detalhes por host (pools e/ou serviços).

---

## 3. YAML de exemplo (AAP / extra-vars)

```yaml
survey_hosts: "srv01,srv02"
motivo: "janela de manutenção"

iis_manage_pools: "sim"
iis_pool_operation: "restart"
iis_pools: ""                # vazio = todos
iis_pool_max_retries: 3

iis_manage_service: "sim"
iis_service_operation: "info"
iis_service_max_retries: 3
```

---

## 4. Execução CLI

```bash
ansible-playbook -i localhost, site.yml \
  -e "survey_hosts=srv01,srv02" \
  -e "motivo=janela de manutenção" \
  -e "iis_manage_pools=sim" \
  -e "iis_pool_operation=restart" \
  -e "iis_pools=" \
  -e "iis_manage_service=sim" \
  -e "iis_service_operation=info"
```

> No AAP as variáveis são preenchidas pelo Survey do template de **IIS Manager**.

---

## 5. Saída / Interpretação do relatório

- **OK**: item atingiu o estado esperado (ou consulta `info` bem-sucedida).
- **NOK**: item não atingiu o estado esperado dentro do limite de retries.
- **absent**: pool/serviço não existe no host.
- **Hosts inalcançáveis**: aparecem em seção separada no e-mail.

Dica rápida:
- Se você quer **somente inventário/consulta**, use `iis_pool_operation=info` e/ou `iis_service_operation=info`.
- Se você quer **ação** em todos os pools, deixe `iis_pools` em branco e selecione `start/stop/restart`.

---
