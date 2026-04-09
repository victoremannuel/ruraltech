# Fluxos Atualizados de Polígonos, Fila RTDB, Auditoria e Eventos

## Resumo Operacional

- Cadastro de propriedade e piquete continua sendo a intenção operacional do app.
- A cerca que realmente governa violação continua sendo a cerca persistida na coleira.
- O backend agora cria `SET_FENCE` automático quando o polígono da propriedade muda.
- O backend agora cria `SET_FENCE` seletivo quando o polígono do piquete ou os `linkedDeviceIds` mudam.
- A RTDB continua sendo o barramento cloud de comandos e eventos.
- A matriz agora escuta a fila por stream RTDB e usa o polling existente como fallback.
- A coleira agora emite `polygon_apply_result` quando conclui com sucesso ou falha a aplicação local de polígono de fazenda, piquete ou condução.
- O log do app agora combina `propertyEvents` com `propertyCommandEvents` para não perder falhas precoces que não geraram evento auditável na coleira.
- Ao abrir um sucesso de gravação no log, o app consulta o polígono atual no Firestore, busca a posição histórica da coleira e renderiza um preview SVG dentro da própria sanfona do evento.

## Prioridade por Fluxo

| Fluxo | Origem de verdade | Camada de propagação | Destino operacional |
| --- | --- | --- | --- |
| Edição de propriedade | Firestore `ruralProperties.points` | Functions -> `loraCommands` -> `matrixCommandQueues` | Coleiras da propriedade |
| Edição de piquete | Firestore `areas.perimeter` + `areas.linkedDeviceIds` | Functions -> `loraCommands` -> `matrixCommandQueues` | Coleiras vinculadas ao piquete |
| Comando genérico do app | Firestore/Supabase queue | RTDB queue + stream da matriz + polling fallback | Coleira/gateway alvo |
| Auditoria de gravação de polígono | Coleira em sucessos/falhas aplicadas localmente; `propertyCommandEvents` em falhas precoces | Matriz -> `propertyEvents` + fallback `propertyCommandEvents` | Log da coleira no app |
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
  participant Event as RTDB propertyEvents/propertyCommands/propertyCommandEvents
  participant AppLog as Log da coleira no app

  App->>FS: salva points + updatedByUid
  FS->>Fn: onWrite
  Fn->>Fn: compara poligono canonico
  Fn->>Lora: cria SET_FENCE deterministico
  Lora->>RTDB: queueValidatedCommand
  RTDB-->>Matriz: stream put/patch
  Matriz->>RTDB: fallback poll quando stream cair
  Matriz->>Coleira: SET_FENCE via LoRa
  Coleira->>Coleira: aplica e persiste NVS
  Coleira-->>Matriz: ACK/NACK + polygon_apply_result
  Matriz-->>Event: propertyCommands + propertyEvents + propertyCommandEvents
  Event-->>AppLog: status, auditoria e fallback
```

Prioridade:
- O app continua definindo a intenção.
- O backend agora é a origem do comando automático.
- A coleira só muda de comportamento quando aplica o `SET_FENCE`.
- O evento `polygon_apply_result` é a confirmação prioritária de gravação local; o trilho de comando só cobre falhas antes desse ponto.

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
  participant AppLog as Log da coleira no app

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
  Coleira-->>Matriz: ACK/NACK + polygon_apply_result
  Matriz-->>AppLog: propertyEvents + propertyCommandEvents
```

Prioridade:
- `areas.linkedDeviceIds` passou a ser a fonte de verdade do vínculo do piquete.
- `collars.activeAreaId` virou espelho operacional/auditoria do vínculo.
- A cerca ativa ainda só muda após aplicação na coleira.
- O log do app mostra sucesso/falha da gravação do piquete com payload bruto e, em caso de sucesso, preview SVG do polígono atual.

### 3. Comando genérico do app -> RTDB stream + polling fallback

```mermaid
flowchart LR
  A[App: SET_FENCE / SET_HERDING_PLAN / SET_PARAMS / PING]
    --> B[Supabase queue-lora-command]
  B --> C[Firestore loraCommands]
  C --> D[Functions queueValidatedCommand]
  D --> E[RTDB matrixCommandQueues com cmd_id e metadados de auditoria]
  E --> F[Stream RTDB da matriz]
  E --> G[Polling RTDB da matriz]
  F --> H[processNextQueuedCommand]
  G --> H
  H --> I[LoRa para coleira/gateway]
  I --> J[ACK/NACK/eventos]
  J --> K[RTDB matrixCommandResults / propertyEvents / propertyCommandEvents]
  K --> L[Firestore espelhos + app]
```

Prioridade:
- A fila RTDB continua sendo a fonte cloud de despacho.
- O stream agora é o gatilho prioritário para despacho imediato.
- O polling antigo permanece como contingência.
- `cmd_id`, `polygon_kind`, `origin_doc_type` e `origin_doc_id` acompanham o fluxo para permitir auditoria ponta a ponta.

### 4. Auditoria e evento -> app

```mermaid
sequenceDiagram
  participant Coleira
  participant Matriz
  participant RTDB as RTDB propertyEvents/propertyTelemetry/propertyCommandEvents
  participant FS as Firestore ruralProperties/areas/herdingOperations
  participant AppLog as Log da coleira no app

  Coleira->>Matriz: EVENT / TELEMETRY / ACK / polygon_apply_result
  Matriz->>RTDB: grava propertyEvents/propertyTelemetry/propertyCommands
  Matriz->>RTDB: grava propertyCommandEvents para falhas de comando
  RTDB-->>AppLog: stream do log consolidado
  AppLog->>FS: consulta poligono atual por origin_doc_type/origin_doc_id
  AppLog->>RTDB: consulta telemetria historica da coleira
  AppLog->>AppLog: renderiza payload + resumo ou SVG do mapa
```

Prioridade:
- Sucesso de gravação nasce na coleira e é a confirmação prioritária.
- Falhas muito precoces podem aparecer primeiro no `propertyCommandEvents`.
- O app usa o banco atual como fonte do polígono exibido e a telemetria histórica como fonte prioritária da posição no mini mapa.
