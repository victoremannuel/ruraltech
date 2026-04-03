# Fluxos Atualizados de Polígonos, Fila RTDB e Eventos

## Resumo Operacional

- Cadastro de propriedade e piquete continua sendo a intenção operacional do app.
- A cerca que realmente governa violação continua sendo a cerca persistida na coleira.
- O backend agora cria `SET_FENCE` automático quando o polígono da propriedade muda.
- O backend agora cria `SET_FENCE` seletivo quando o polígono do piquete ou os `linkedDeviceIds` mudam.
- A RTDB continua sendo o barramento cloud de comandos e eventos.
- A matriz agora escuta a fila por stream RTDB e usa o polling existente como fallback.
- Eventos operacionais continuam nascendo na coleira e sendo espelhados pela matriz/backend para o app.

## Prioridade por Fluxo

| Fluxo | Origem de verdade | Camada de propagação | Destino operacional |
| --- | --- | --- | --- |
| Edição de propriedade | Firestore `ruralProperties.points` | Functions -> `loraCommands` -> `matrixCommandQueues` | Coleiras da propriedade |
| Edição de piquete | Firestore `areas.perimeter` + `areas.linkedDeviceIds` | Functions -> `loraCommands` -> `matrixCommandQueues` | Coleiras vinculadas ao piquete |
| Comando genérico do app | Firestore/Supabase queue | RTDB queue + stream da matriz + polling fallback | Coleira/gateway alvo |
| Evento operacional | Coleira | Matriz -> RTDB/Firestore | App e notificações |

## Diagramas

### 1. Propriedade -> auto `SET_FENCE`

```mermaid
sequenceDiagram
  participant App
  participant FS as Firestore ruralProperties
  participant Fn as Functions autoSyncPropertyFence
  participant Lora as Firestore loraCommands
  participant RTDB as RTDB matrixCommandQueues
  participant Matriz
  participant Coleira
  participant Event as RTDB propertyEvents/propertyCommands

  App->>FS: salva points + updatedByUid
  FS->>Fn: onWrite
  Fn->>Fn: compara poligono canonico
  Fn->>Lora: cria SET_FENCE deterministico
  Lora->>RTDB: queueValidatedCommand
  RTDB-->>Matriz: stream put/patch
  Matriz->>RTDB: fallback poll quando stream cair
  Matriz->>Coleira: SET_FENCE via LoRa
  Coleira->>Coleira: aplica e persiste NVS
  Coleira-->>Matriz: ACK / eventos
  Matriz-->>Event: propertyCommands + propertyEvents
  Event-->>App: status e eventos
```

Prioridade:
- O app continua definindo a intenção.
- O backend agora é a origem do comando automático.
- A coleira só muda de comportamento quando aplica o `SET_FENCE`.

### 2. Piquete + `linkedDeviceIds` -> auto `SET_FENCE` seletivo

```mermaid
sequenceDiagram
  participant App
  participant FS as Firestore areas
  participant Fn as Functions autoSyncAreaFence
  participant Collar as Firestore collars
  participant Lora as Firestore loraCommands
  participant RTDB as RTDB matrixCommandQueues
  participant Matriz
  participant Coleira

  App->>FS: salva perimeter + linkedDeviceIds + updatedByUid
  FS->>Fn: onWrite
  Fn->>Collar: sincroniza activeAreaId nas vinculadas
  Fn->>Fn: ignora source=herding_operation
  Fn->>Lora: cria SET_FENCE so para linkedDeviceIds
  Lora->>RTDB: queueValidatedCommand
  RTDB-->>Matriz: stream put/patch
  Matriz->>RTDB: poll fallback
  Matriz->>Coleira: envia SET_FENCE seletivo
  Coleira->>Coleira: aplica cerca do piquete
```

Prioridade:
- `areas.linkedDeviceIds` passou a ser a fonte de verdade do vínculo do piquete.
- `collars.activeAreaId` virou espelho operacional/auditoria do vínculo.
- A cerca ativa ainda só muda após aplicação na coleira.

### 3. Comando genérico do app -> RTDB stream + polling fallback

```mermaid
flowchart LR
  A[App: SET_FENCE / SET_HERDING_PLAN / SET_PARAMS / PING]
    --> B[Supabase queue-lora-command]
  B --> C[Firestore loraCommands]
  C --> D[Functions queueValidatedCommand]
  D --> E[RTDB matrixCommandQueues]
  E --> F[Stream RTDB da matriz]
  E --> G[Polling RTDB da matriz]
  F --> H[processNextQueuedCommand]
  G --> H
  H --> I[LoRa para coleira/gateway]
  I --> J[ACK/NACK/eventos]
  J --> K[RTDB matrixCommandResults / propertyEvents]
  K --> L[Firestore espelhos + app]
```

Prioridade:
- A fila RTDB continua sendo a fonte cloud de despacho.
- O stream agora é o gatilho prioritário para despacho imediato.
- O polling antigo permanece como contingência.

### 4. Evento da coleira -> app

```mermaid
sequenceDiagram
  participant Coleira
  participant Matriz
  participant RTDB as RTDB propertyEvents/propertyTelemetry
  participant Fn as Functions mirrors/push
  participant FS as Firestore events/herdingOperations
  participant App

  Coleira->>Matriz: EVENT / TELEMETRY / ACK
  Matriz->>RTDB: grava propertyEvents/propertyTelemetry/propertyCommands
  RTDB->>Fn: triggers de espelho
  Fn->>FS: events / herdingOperations / loraCommands
  RTDB-->>App: stream em tempo real
  FS-->>App: historico, status e notificacoes
```

Prioridade:
- O evento nasce na coleira.
- A matriz publica e roteia.
- RTDB e Firestore passam a ser espelhos consumidos pelo app.
