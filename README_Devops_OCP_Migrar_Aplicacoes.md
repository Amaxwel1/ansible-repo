# Devops OCP - Migração de Aplicações entre Clusters

Playbook/Workflow responsável por **migrar aplicações entre clusters OpenShift** por meio da alteração do atributo `replicas` de objetos `DeploymentConfig`.

A automação identifica os objetos no cluster de origem, aplica filtros definidos no Survey, respeita grupos e regras de ordenação, executa `scale down` na origem quando aplicável, executa `scale up` no destino e consolida o resultado em um **relatório HTML** enviado por job separado.

O workflow principal encadeia dois templates:

- **`Devops_OCP_Migrar_Aplicações`**: realiza a migração dos objetos entre clusters OpenShift.
- **`Devops_Send_Email`**: envia o relatório da execução para o time DevOps.

> Observação: o envio SMTP é feito por **job separado**. Este play consolida e publica `send_mail_subject`, `send_mail_body`, `send_mail_attachments` e demais variáveis necessárias para o job de e-mail.

---

## 1. Variáveis

| Variável | Tipo | Descrição |
| --- | --- | --- |
| `cluster_active` | string | Cluster de origem. Valores esperados: `OSASCO` ou `ALPHAVILLE`. |
| `cluster_migration` | string | Cluster de destino. Valores esperados: `OSASCO` ou `ALPHAVILLE`. |
| `ocp_user` | string | Usuário utilizado para autenticação no OpenShift. |
| `ocp_password` | string | Senha utilizada para autenticação no OpenShift. Normalmente preenchida como campo criptografado no Survey. |
| `aplication_migration` | list | Lista de aplicações/grupos/conjuntos a migrar. Ex.: `["BIL", "DDS"]`. Opções esperadas: `BIL`, `DIL`, `DDS`, `VALEMOBI`, `PAGINAS DE MANUTENCAO`, `SINV`, `ALL`. |
| `perform_scale_down` | string | Define se os objetos devem ser baixados na origem. Valores: `SIM` ou `NAO`. |
| `migrar_paginas_manutencao` | string | Define se os objetos listados em `paginas_manutencao` devem participar da migração. Valores: `SIM` ou `NAO`. |
| `migrar_sinv` | string | Define se os objetos especiais do `sinv` devem participar da migração. Valores: `SIM` ou `NAO`. |
| `baixar_dds` | string | Define se objetos do grupo `DDS` devem ser baixados na origem. Valores: `SIM` ou `NAO`. |
| `condicao_progresso` | string | Estado/condição de Pod esperado para avançar na migração. Ex.: `Pending`, `Running`, `Ready`, `Succeeded`. |
| `async_batch` | integer | Quantidade de namespaces processados em paralelo no fluxo paralelizado. |
| `async_dc_batch` | integer | Quantidade de DeploymentConfigs processados em paralelo dentro de cada namespace. |
| `wait_poll_interval` | integer | Intervalo, em segundos, entre consultas de validação de Pods durante waits de scale down/scale up. |
| `exclude_namespaces` | string | Lista de namespaces a desconsiderar, separados por vírgula. Ex.: `ns-a,ns-b`. |
| `exclude_deployments` | string | Lista de DeploymentConfigs a desconsiderar no padrão `namespace/dc`, separados por vírgula. |
| `deployments_toquery` | string | Lista de DeploymentConfigs específicos a migrar no padrão `namespace/dc`, separados por vírgula. |
| `labels` | string | Lista de labels usadas para filtrar DeploymentConfigs. Ex.: `app=database,tier=backend`. |
| `scale_down_timeout` | dict | Configuração de timeout para espera do scale down na origem. Contém `seconds` e `action`. |
| `pod_phases_timeout` | dict | Configuração de timeout para estados do tipo Pod phase, como `Pending`, `Running`, `Succeeded`. |
| `pod_conditions_timeout` | dict | Configuração de timeout para condições do Pod, como `Ready`, `Initialized`, `ContainersReady`. |
| `final_pod_validation_enabled` | string | Habilita a validação final dos Pods no destino. Valores: `SIM` ou `NAO`. |
| `final_pod_validation_retries` | integer | Número de tentativas da validação final dos Pods. |
| `final_pod_validation_delay` | integer | Intervalo, em segundos, entre tentativas da validação final dos Pods. |
| `tmp_path_local` | string | Diretório temporário usado para kubeconfigs, scripts e logs. |
| `send_mail_cifs` | string | Ambiente/entrada usada para resolver o CIFS de destino dos anexos. |
| `send_mail_cifs_path` | string | Caminho no CIFS onde o log completo será publicado. |

---

## 2. Estrutura esperada

- **`playbook.yaml`**  
  Arquivo principal da automação. Realiza autenticação nos clusters, pesquisa namespaces e DeploymentConfigs, aplica filtros, monta listas de execução, chama os fluxos sequencial/paralelizado, consolida logs e prepara o relatório.

- **`grupos.yml`**  
  Arquivo de configuração dos grupos principais e conjuntos especiais. Contém:
  - `aplicacoes`: grupos pesquisados por prefixo de namespace;
  - `paginas_manutencao`: objetos especiais de páginas de manutenção;
  - `sinv`: objetos especiais do SINV.

- **`group_namespaces_order/<GRUPO>.yml`**  
  Arquivos opcionais para controlar a ordem de migração de namespaces e, opcionalmente, a ordem dos DeploymentConfigs dentro deles.

- **`execute_ns_sync.yml`**  
  Executa a migração dos namespaces que fazem parte da lista ordenada. Pode processar DCs em modo sequencial ou paralelo, dependendo da configuração do arquivo de ordem.

- **`execute_ns_async.yml`**  
  Dispara a execução paralelizada dos namespaces que não fazem parte da lista ordenada.

- **`templates/execute_ns_async.sh.j2`**  
  Template Bash utilizado no fluxo paralelizado. Controla os lotes de DCs por namespace com base em `async_dc_batch`.

- **Job de e-mail separado**  
  Consome os dados publicados via `set_stats` e envia o relatório final.

---

## 3. YAML de exemplo

### 3.1 `grupos.yml`

```yaml
aplicacoes:
  - grupo: BIL
    condition_towait: Ready
    namespaces_prefix:
      - ag-bkg-teste-ansible-bil
      - ag-bkg-teste-ansible-business

  - grupo: DIL
    condition_towait: Ready
    namespaces_prefix:
      - ag-bkg-teste-ansible-dil

  - grupo: DDS
    namespaces_prefix:
      - ag-bkg-teste-ansible-valemobi-dds
      - ag-bkg-teste-ansible-valemobi-2

  - grupo: VALEMOBI
    namespaces_prefix:
      - ag-bkg-teste-ansible-valemobi

paginas_manutencao:
  - namespace: ag-bkg-teste-ansible-dil-1
    dc:
      - webserver-ag-bkg-teste-ansible-dil-1

  - namespace: ag-bkg-teste-ansible-valemobi-1
    dc:
      - application-ag-bkg-teste-ansible-valemobi-1

sinv:
  - namespace: ag-bkg-teste-ansible-sinv-1
    dc:
      - application-ag-bkg-teste-ansible-sinv-1
      - webserver-ag-bkg-teste-ansible-sinv-1

  - namespace: ag-bkg-teste-ansible-sinv-2
    dc:
      - application-ag-bkg-teste-ansible-sinv-2
```

### 3.2 `group_namespaces_order/BIL.yml` com ordem explícita de DCs

Quando a chave `dc` é definida, os DCs são processados **um por vez** e na ordem informada.

```yaml
- namespace: ag-bkg-teste-ansible-bil-1
  dc:
    - database-ag-bkg-teste-ansible-bil-1
    - webserver-ag-bkg-teste-ansible-bil-1
    - application-ag-bkg-teste-ansible-bil-1

- namespace: ag-bkg-teste-ansible-business-2
  dc:
    - application-ag-bkg-teste-ansible-business-2
    - webserver-ag-bkg-teste-ansible-business-2
    - database-ag-bkg-teste-ansible-business-2
```

### 3.3 `group_namespaces_order/DIL.yml` apenas com namespace

Quando a chave `dc` **não** é definida, a automação respeita a ordem dos namespaces, mas processa os DCs encontrados dentro do namespace em paralelo, respeitando `async_dc_batch`.

```yaml
- namespace: ag-bkg-teste-ansible-dil-2
- namespace: ag-bkg-teste-ansible-dil-1
```

Neste exemplo:

1. `ag-bkg-teste-ansible-dil-2` executa antes de `ag-bkg-teste-ansible-dil-1`;
2. dentro de cada namespace, os DCs podem rodar em paralelo;
3. a quantidade de DCs paralelos é limitada por `async_dc_batch`.

### 3.4 Variáveis de execução no AAP

```yaml
cluster_active: OSASCO
cluster_migration: ALPHAVILLE

perform_scale_down: "SIM"
migrar_paginas_manutencao: "NAO"
migrar_sinv: "NAO"
baixar_dds: "NAO"

condicao_progresso: Running

async_batch: 20
async_dc_batch: 3
wait_poll_interval: 2

aplication_migration:
  - BIL
  - VALEMOBI

exclude_namespaces: ""
exclude_deployments: ""
deployments_toquery: ""
labels: ""

final_pod_validation_enabled: "SIM"
final_pod_validation_retries: 3
final_pod_validation_delay: 10
```

---

## 4. Execução

### 4.1 Execução via AAP

No AAP, a execução é feita pelo workflow:

```text
WF_Devops_OCP_Migrar_Aplicações
```

O usuário deve acessar **Templates**, pesquisar o workflow e clicar em **Launch**.  
Os campos do Survey definem origem, destino, grupos, filtros e comportamento da migração.

### 4.2 Execução via CLI

Exemplo para execução local do playbook principal:

```bash
ansible-playbook -i localhost, playbook.yaml \
  -e "cluster_active=OSASCO" \
  -e "cluster_migration=ALPHAVILLE" \
  -e "ocp_user=ansible" \
  -e "ocp_password='senha'" \
  -e "perform_scale_down=SIM" \
  -e "migrar_paginas_manutencao=NAO" \
  -e "migrar_sinv=NAO" \
  -e "baixar_dds=NAO" \
  -e "condicao_progresso=Running" \
  -e '{"aplication_migration":["BIL","VALEMOBI"]}'
```

> Em produção, a execução normalmente deve ocorrer pelo AAP, pois o Survey e as credenciais já estarão configurados.

---

## 5. Comportamento da automação

### 5.1 Pesquisa dos objetos

A automação executa as seguintes etapas:

1. autentica no cluster de origem e no cluster de destino;
2. valida o acesso ao CIFS usado para publicação do log;
3. monta a lista de grupos a partir de `aplication_migration`;
4. pesquisa namespaces usando os prefixos definidos em `grupos.yml`;
5. pesquisa DeploymentConfigs nos namespaces encontrados;
6. aplica filtros de inclusão, exclusão e labels;
7. adiciona listas especiais, como `paginas_manutencao` e `sinv`, quando selecionadas;
8. remove páginas de manutenção ou SINV da lista final quando as flags estiverem como `NAO`;
9. monta a lista sequencial e a lista paralelizada.

### 5.2 Grupos principais e conjuntos especiais

- `BIL`, `DIL`, `DDS` e `VALEMOBI` são grupos principais definidos em `aplicacoes`.
- `PAGINAS DE MANUTENCAO` é um conjunto especial definido em `paginas_manutencao`.
- `SINV` é um conjunto especial definido em `sinv`.

Os conjuntos especiais não precisam ter arquivo próprio em `group_namespaces_order`.

### 5.3 Regra de `ALL`

Ao selecionar `ALL`, a automação considera os grupos principais definidos em `aplicacoes`.

Os conjuntos especiais `PAGINAS DE MANUTENCAO` e `SINV` devem ser selecionados conforme a configuração esperada no Survey para que seus objetos especiais sejam considerados.

---

## 6. Modos de execução

### 6.1 Migração sequencial com DCs ordenados

Quando um namespace aparece em `group_namespaces_order/<GRUPO>.yml` com a chave `dc`, a automação processa os DCs **um por vez**, respeitando exatamente a ordem declarada.

Exemplo:

```yaml
- namespace: ag-bkg-teste-ansible-dil-1
  dc:
    - database-ag-bkg-teste-ansible-dil-1
    - webserver-ag-bkg-teste-ansible-dil-1
    - application-ag-bkg-teste-ansible-dil-1
```

Execução esperada:

```text
database -> webserver -> application
```

Esse modo deve ser usado quando existe dependência entre os componentes.

### 6.2 Migração sequencial com DCs paralelos

Quando um namespace aparece em `group_namespaces_order/<GRUPO>.yml` **sem** a chave `dc`, a automação respeita apenas a ordem do namespace, mas processa os DCs do namespace em paralelo, usando `async_dc_batch`.

Exemplo:

```yaml
- namespace: namespaceB
- namespace: namespaceA
```

Execução esperada:

```text
namespaceB: DCs em paralelo por lote
namespaceA: DCs em paralelo por lote
```

A ordem dos namespaces continua sendo respeitada: `namespaceB` termina antes de `namespaceA` começar.

Esse modo é útil quando o cliente quer controlar a ordem entre namespaces, mas não há dependência entre os DCs dentro do mesmo namespace.

### 6.3 Migração paralelizada

Os objetos que não constam em arquivos de ordenação entram no fluxo paralelizado.

Esse fluxo possui dois níveis de paralelismo:

1. **Paralelismo por namespace**, controlado por `async_batch`;
2. **Paralelismo por DC dentro do namespace**, controlado por `async_dc_batch`.

Exemplo:

```yaml
async_batch: 2
async_dc_batch: 2
```

Nesse caso, a automação pode processar até:

```text
2 namespaces em paralelo x 2 DCs por namespace = 4 fluxos de DCs simultâneos
```

Cada DC executa seu fluxo completo de forma independente:

1. valida existência no destino;
2. scale down na origem, se aplicável;
3. espera scale down;
4. scale up no destino;
5. espera condição de Pod.

---

## 7. Etapas da migração de cada DeploymentConfig

Para cada DeploymentConfig selecionado, a automação segue o fluxo abaixo:

1. **Valida Current Pods na origem**

   A automação verifica se o DeploymentConfig possui Current Pods maior que zero no cluster de origem.

   - Se sim, continua.
   - Se não, o objeto não é migrado e é registrado como `Current Pods igual a zero`.

2. **Valida existência do DeploymentConfig no destino**

   Antes de baixar a origem, a automação verifica se o DeploymentConfig existe no cluster de destino.

   - Se existir, continua.
   - Se não existir, a automação **não baixa a origem**, registra a ocorrência como `Objeto não encontrado no cluster de destino` e segue para o próximo objeto.

   Esse comportamento evita baixar uma aplicação na origem quando não há objeto correspondente no destino.

3. **Executa scale down na origem, se aplicável**

   Se `perform_scale_down` estiver como `SIM`, a automação atribui `replicas=0` no cluster de origem.

   Exceção: se o objeto pertencer ao grupo `DDS` e `baixar_dds` estiver como `NAO`, o scale down é ignorado para o DDS.

4. **Aguarda scale down**

   A automação consulta o cluster de origem até não encontrar Pods em estado `Running` para aquele DeploymentConfig.

   O intervalo entre consultas é definido por `wait_poll_interval`.

5. **Executa scale up no destino**

   A automação atribui `replicas=1` no DeploymentConfig correspondente no cluster de destino.

6. **Aguarda estado/condição do Pod no destino**

   A automação aguarda encontrar pelo menos um Pod no estado ou condição configurada.

   - Em itens sequenciais, se o grupo possuir `condition_towait` em `grupos.yml`, ela é usada.
   - Caso contrário, é usada `condicao_progresso` do Survey.
   - Em itens paralelizados, é usada `condicao_progresso`.

7. **Registra timeout, se houver**

   Timeouts são registrados no log completo da execução, mas não são mais exibidos como seção principal no e-mail.

---

## 8. Regras especiais

### 8.1 Páginas de manutenção

Objetos de páginas de manutenção são configurados em `grupos.yml`, na chave `paginas_manutencao`.

- `migrar_paginas_manutencao = SIM`: os objetos são migrados normalmente.
- `migrar_paginas_manutencao = NAO`: os objetos são removidos da lista final e não são migrados.

### 8.2 SINV

Objetos do SINV são configurados em `grupos.yml`, na chave `sinv`.

- `migrar_sinv = SIM`: os objetos são migrados normalmente.
- `migrar_sinv = NAO`: os objetos são removidos da lista final e não são migrados.

### 8.3 DDS

O grupo DDS é definido em `aplicacoes`.

A variável `baixar_dds` controla somente o scale down na origem para objetos DDS.

- `baixar_dds = SIM`: objetos DDS seguem a regra global `perform_scale_down`.
- `baixar_dds = NAO`: objetos DDS não são baixados na origem, mesmo que `perform_scale_down = SIM`.

`baixar_dds` não remove objetos da migração. Ele apenas controla o scale down no cluster de origem.

---

## 9. Timeouts

### 9.1 Scale down

A variável `scale_down_timeout` define:

```yaml
scale_down_timeout:
  seconds: 300
  action: stop_namespace
```

Ações possíveis:

- `ignore`: registra o timeout e continua para o scale up.
- `stop_dc`: cancela o scale up daquele DC e segue para o próximo DC.
- `stop_namespace`: interrompe a migração daquele namespace.

### 9.2 Espera de Pods no destino

As variáveis `pod_phases_timeout` e `pod_conditions_timeout` definem o tempo e a ação para cada estado/condição.

Exemplo:

```yaml
pod_phases_timeout:
  Pending:
    seconds: 300
    action: ignore
  Running:
    seconds: 300
    action: ignore
  Succeeded:
    seconds: 300
    action: ignore

pod_conditions_timeout:
  Ready:
    seconds: 600
    action: stop_namespace
```

Ações possíveis:

- `ignore`: registra o timeout e segue para o próximo DC.
- `stop_namespace`: interrompe a migração do namespace.

### 9.3 Timeouts no relatório

Os timeouts continuam sendo registrados no log completo, pois são úteis para troubleshooting e auditoria.

Porém, o e-mail não utiliza mais uma seção de timeouts como indicador principal. O status final é baseado na validação final dos Pods no cluster de destino.

---

## 10. Validação final dos Pods no destino

Após a migração, a automação valida os Pods nos namespaces afetados no cluster de destino.

A validação busca Pods que ainda exigem atenção, como:

- `Pending`;
- `Failed`;
- `Unknown`;
- `Running` com containers não prontos;
- `ImagePullBackOff`;
- `ErrImagePull`;
- `CrashLoopBackOff`;
- `Error`;
- `Terminating`;
- `ContainersNotReady`.

Pods históricos de deploy com:

```text
phase = Succeeded
reason = Completed
```

são ignorados, pois são esperados no ciclo de vida de DeploymentConfigs do OpenShift e não representam falha operacional.

O resultado aparece no e-mail na seção:

```text
Validação final dos pods no destino
```

---

## 11. Saída

### 11.1 Resultado esperado

- **SUCESSO**: migração concluída sem pods com atenção, sem objetos ausentes no destino e sem objetos ignorados por Current Pods zero.
- **CONCLUÍDO COM ATENÇÃO**: migração terminou, mas o relatório identificou pelo menos uma ocorrência que exige análise.

### 11.2 Relatório HTML

O relatório HTML contém:

- Cabeçalho com status da execução;
- Cards de resumo:
  - duração total;
  - Pods com atenção;
  - objetos não encontrados;
  - objetos com Current Pods zero;
- Parâmetros da execução;
- Filtros aplicados;
- Resultado da execução;
- Validação final dos Pods no destino;
- Namespaces da migração sequencial;
- Namespaces da migração paralelizada;
- DeploymentConfigs não encontrados no destino;
- Objetos desconsiderados por Current Pods zero;
- Referência ao log completo anexado.

### 11.3 Artefatos publicados

A automação publica via `set_stats`:

- `send_mail_subject`;
- `send_mail_body`;
- `send_mail_attachments`;
- `send_mail_cifs`.

O job de e-mail separado consome esses valores para envio do relatório.

---

## 12. Exemplos de uso

### 12.1 Migrar somente BIL

```yaml
aplication_migration:
  - BIL
perform_scale_down: "SIM"
condicao_progresso: Running
```

Resultado esperado:

- pesquisa namespaces com prefixos do grupo BIL;
- aplica ordem de `group_namespaces_order/BIL.yml`, se existir;
- baixa origem e sobe destino.

### 12.2 Migrar DDS sem baixar origem

```yaml
aplication_migration:
  - DDS
perform_scale_down: "SIM"
baixar_dds: "NAO"
```

Resultado esperado:

- objetos DDS são migrados para o destino;
- objetos DDS não recebem `replicas=0` na origem.

### 12.3 Migrar SINV

```yaml
aplication_migration:
  - SINV
migrar_sinv: "SIM"
```

Resultado esperado:

- objetos definidos em `sinv` são pesquisados e incluídos na migração.

### 12.4 Controlar ordem de namespaces, mas paralelizar DCs

Arquivo `group_namespaces_order/DIL.yml`:

```yaml
- namespace: ag-bkg-dil-2
- namespace: ag-bkg-dil-1
```

Variável:

```yaml
async_dc_batch: 3
```

Resultado esperado:

- `ag-bkg-dil-2` executa antes de `ag-bkg-dil-1`;
- dentro de cada namespace, até 3 DCs rodam em paralelo.

### 12.5 Evitar baixar origem quando objeto não existe no destino

Cenário:

- DC existe na origem;
- DC não existe no destino.

Resultado esperado:

- a automação não executa scale down na origem;
- registra a ocorrência como objeto não encontrado;
- segue para o próximo objeto;
- o e-mail mantém a seção de `DeploymentConfigs não encontrados no cluster de destino`.

---

## 13. Observações importantes

- A variável `baixar_dds` não remove DDS da migração; ela só impede o scale down na origem para o grupo DDS.
- `migrar_paginas_manutencao` e `migrar_sinv` controlam inclusão/remoção dos objetos especiais da lista final.
- Quando um namespace está em `group_namespaces_order` sem `dc`, a ordem do namespace é respeitada, mas os DCs são paralelizados.
- Quando um namespace está em `group_namespaces_order` com `dc`, a ordem dos DCs é respeitada.
- Timeouts continuam no log completo, mas a análise final do e-mail se baseia na validação final dos Pods.
- Pods `Succeeded/Completed` de deploy não aparecem como problema no relatório.
