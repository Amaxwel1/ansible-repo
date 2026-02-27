# Portas de Webhook em Rulebooks (EDA) — Padrão e Controle

Este documento centraliza as **portas usadas por Rulebooks que expõem webhook** (`ansible.eda.webhook`) no AAP EDA, evitando conflito entre activations e garantindo padronização.

---

## 1. Por que isso é importante?

Cada Rulebook Activation que utiliza `ansible.eda.webhook` inicia um listener HTTP em uma **porta fixa**.

Se duas activations tentarem subir listeners na **mesma porta**, ocorre conflito (“porta em uso”), e uma das activations pode falhar ou ficar instável.

---

## 2. Padrão recomendado

- Manter uma **porta exclusiva por rulebook/uso**.
- Reservar um range dedicado para webhooks de EDA (ex.: `5000–5099`).
- Registrar sempre:
  - Porta
  - Nome do Rulebook/Activation
  - Objetivo/monitoramento
  - Responsável/Time
  - Ambiente (DEV/HML/PRD)
  - Data da última alteração

---

## 3. Mapa atual de portas

| Porta | Rulebook / Activation | Finalidade | Observações |
|------:|------------------------|-----------|------------|
| 5000  | Monitoramento da B3    | Webhook para eventos do monitoramento B3 | Porta reservada |
| 5001  | Monitoramento de Logs DB | Webhook para eventos de falha/OK de logs/conexão DB | Porta reservada |

> **Atenção:** antes de criar um novo webhook, atualize esta tabela.

---

## 4. Modelo de configuração (Rulebook)

Exemplo com `ansible.eda.webhook`:

```yaml
sources:
  - name: webhook_in
    ansible.eda.webhook:
      host: "0.0.0.0"
      port: 5001
```

---

## 5. Checklist antes de subir uma nova Activation

1. Verificar se a porta já está reservada no “Mapa atual de portas”.
2. Se não estiver, escolher a próxima porta livre no range.
3. Atualizar este documento com a nova reserva.
4. Validar a activation em ambiente de teste antes de promover.

---

## 6. Testes rápidos

### 6.1 Teste via curl (local / port-forward)

```bash
curl -sS -X POST http://127.0.0.1:5001   -H "Content-Type: application/json"   -d '{"type":"test","msg":"hello"}'
```

### 6.2 Teste de porta em uso (Linux)

```bash
ss -lntp | egrep ':5000|:5001'
```

---

## 7. Controle de mudanças

| Data | Alteração | Responsável |
|------|----------|-------------|
| 2026-02-27 | Reservadas portas 5000 (B3) e 5001 (Logs DB) | Alex |
