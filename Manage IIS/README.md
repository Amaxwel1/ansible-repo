# IIS Manager (Windows) - Ansible/AAP

Automação para **gerenciar IIS Application Pools** e **serviços do IIS** em hosts Windows via WinRM.

## Variáveis (Survey)

- `survey_hosts` (obrigatório): string com hosts separados por vírgula (`host1,host2,...`)
- `ansible_user` / `ansible_password` (obrigatório)
- `motivo` (opcional)

### Campos "Sim/Não" no Survey
Para deixar o Survey mais amigável, os campos abaixo podem vir como **"Sim"** ou **"Não"**.

- Aceitos como **Sim**: `sim`, `s`, `yes`, `y`, `true`, `1`, `on`
- Aceitos como **Não**: `nao`, `não`, `n`, `no`, `false`, `0`, `off`

> Observação: também funciona se o Survey enviar `true/false` (boolean).

### Application Pools
- `iis_manage_pools` (default: `Sim`) — habilita/desabilita gestão de pools
- `iis_pools` (opcional) — lista ou string `PoolA,PoolB`; se vazio/ausente = **todos os pools**
- `iis_pool_operation` (default: `start`) — `start` | `stop` | `restart`
- `iis_pool_max_retries` (default: `3`) — tentativas para atingir o estado esperado

### Serviços IIS
- `iis_manage_service` (default: `Não`) — habilita/desabilita gestão de serviços
- `iis_services` (default: `W3SVC`) — lista ou string `W3SVC,WAS` etc.
- `iis_service_operation` (default: `restart`) — `start` | `stop` | `restart`
- `iis_service_max_retries` (default: `3`) — tentativas para atingir o estado esperado

## Saída

- Por host: `iis_host_report`
- Em `set_stats`:
  - `send_mail_subject`
  - `send_mail_body`

## Observações

- Requer o módulo **WebAdministration** no Windows (IIS instalado). Se não existir, o host entra como erro no relatório.
- Para "reiniciar todos os pools": deixe `iis_pools` vazio e use `iis_pool_operation=restart`.
- Para "reiniciar um pool": defina `iis_pools=NomeDoPool` e `iis_pool_operation=restart`.
- Para "reiniciar o serviço do IIS": habilite `iis_manage_service=Sim` e use `iis_service_operation=restart`.
