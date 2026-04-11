# Architecture: Requisitos — RuralTech

## Overview

Requisitos funcionais e não funcionais do sistema de pecuária de precisão.

## Components

### Requisitos Funcionais (RF)

#### RF01 — Autenticação
- RF01.1: Login com email/senha via Supabase Auth
- RF01.2: Sessão persistente no app
- RF01.3: Diferenciação de papéis: `user` e `adm/admin`

#### RF02 — Gestão de Propriedades
- RF02.1: Criar, editar e excluir propriedades rurais
- RF02.2: Definir polígono da propriedade no mapa (3–32 pontos)
- RF02.3: Associar usuários à propriedade (`user_uids`)
- RF02.4: Vincular gateways e coleiras à propriedade
- RF02.5: Ao editar polígono, sistema envia `SET_FENCE` automático a todas as coleiras da propriedade

#### RF03 — Gestão de Piquetes (Areas)
- RF03.1: Criar e editar piquetes dentro de uma propriedade
- RF03.2: Definir polígono do piquete (3–32 pontos)
- RF03.3: Vincular coleiras ao piquete (`linkedDeviceIds`)
- RF03.4: Ao editar piquete ou vínculo, sistema envia `SET_FENCE` seletivo às coleiras vinculadas

#### RF04 — Gestão de Coleiras
- RF04.1: Listar coleiras por propriedade
- RF04.2: Visualizar posição GPS da coleira no mapa em tempo real
- RF04.3: Ver status (online/offline/unknown) e health diário
- RF04.4: Enviar comando `SET_FENCE` manualmente para coleira específica
- RF04.5: Enviar comando `SET_PARAMS` (incluindo controle Wi-Fi/OTA)
- RF04.6: Enviar comando `PING`
- RF04.7: Ver log de eventos e telemetria da coleira (CollarLogScreen)
- RF04.8: Ver detalhes de saúde (GPS, LoRa, MPU, MLX, armazenamento, temperatura, uptime)
- 

#### RF05 — Gestão de Gateways
- RF05.1: Listar gateways por propriedade
- RF05.2: Ver status do gateway (online/offline)
- RF05.3: Conectar ao gateway local via WebSocket (porta 81)
- RF05.4: Receber telemetria em tempo real via WS do gateway local
- RF05.5: Descoberta de gateway na rede local via Bluetooth/scanning
- RF05.6: Controlar Wi-Fi OTA do gateway

#### RF06 — Geofence Manual
- RF06.1: Editor de polígono no mapa para coleira específica
- RF06.2: Carregar cerca salva anteriormente
- RF06.3: Adicionar/desfazer/limpar pontos
- RF06.4: Publicar cerca (salva no Supabase + enfileira SET_FENCE)

#### RF07 — Condução de Rebanho (Herding)
- RF07.1: Selecionar propriedade e coleiras alvo
- RF07.2: Desenhar polígono destino no mapa
- RF07.3: Enviar operação de herding (cria `herding_operations`)
- RF07.4: Acompanhar status da operação em tempo real
- RF07.5: Opcionalmente promover polígono a piquete permanente
- RF07.6: Visualizar histórico de operações

#### RF08 — Telemetria e Eventos
- RF08.1: Mapa principal exibe posições das coleiras em tempo real
- RF08.2: Histórico de posições por dia (property_telemetry_history)
- RF08.3: Log de eventos combinado (propertyEvents + propertyCommandEvents)
- RF08.4: Preview SVG do polígono no evento de sucesso de gravação
- RF08.5: Filtro de mapa por propriedade, piquete, coleira, gateway

#### RF09 — Auditoria de Comandos
- RF09.1: Rastrear cada comando por `cmd_id` único
- RF09.2: Exibir status do comando (enfileirado, despachado, aplicado, falhou)
- RF09.3: Associar comando ao documento de origem (`origin_doc_type`, `origin_doc_id`)
- RF09.4: Exibir preview de mapa para eventos de polígono bem-sucedidos

#### RF10 — Administração (role adm/admin)
- RF10.1: Visualizar todas as propriedades
- RF10.2: Gerenciar usuários e papéis
- RF10.3: Enviar SET_PARAMS com wifi_ota_enabled=false
- RF10.4: Ver bindings de matriz e filas de comandos

### Requisitos Não Funcionais (RNF)

#### RNF01 — Performance
- RNF01.1: Payload LoRa ≤ 128 bytes por frame; fragmentação automática para maiores
- RNF01.2: Nenhum N+1 em queries Supabase; preferir queries consolidadas
- RNF01.3: Batch de operações em escrita em massa
- RNF01.4: Descoberta de rede local em lotes (batch probing)
- RNF01.5: Listagens com limite paginado (?limit=n)

#### RNF02 — Confiabilidade
- RNF02.1: Operação offline-first na coleira (geofence e herding funcionam sem conectividade)
- RNF02.2: Deduplicação de comandos via `cmd_id` determinístico
- RNF02.3: Stream RTDB como caminho primário; polling como fallback
- RNF02.4: Health diário reportado pela coleira para detectar falhas de hardware
- RNF02.5: Hash chain em logs locais do gateway

#### RNF03 — Segurança
- RNF03.1: Toda escrita no Supabase protegida por RLS policies
- RNF03.2: Edge Functions validam `matrixId + writerKey` para escrita anônima
- RNF03.3: Ações administrativas exigem marcador de role explícito
- RNF03.4: Nenhum segredo commitado (manual_settings.local.h, chaves, tokens)
- RNF03.5: Inputs de coordenadas, IDs e JSON sanitizados antes de persistir

#### RNF04 — Manutenibilidade
- RNF04.1: Contratos de mensagem centralizados em `contracts/messages/` (JSON fixtures)
- RNF04.2: Validação de contrato compartilhada em `firmware/shared/command_contract.*`
- RNF04.3: CI gates obrigatórios: flutter analyze, flutter test, firmware compile, pgTAP
- RNF04.4: Erros de negócio sempre retornam `reason` acionável
- RNF04.5: Nenhuma falha silenciosa em regras de negócio
- RNF04.6: Somente `CloudService` acessa Supabase no app (screens/widgets não acessam diretamente)

#### RNF05 — Escalabilidade
- RNF05.1: Supabase Realtime para telemetria em tempo real (sem polling do app)
- RNF05.2: Tabelas de histórico particionadas por `day_key`
- RNF05.3: Índices GIN em arrays (`user_uids`, `linked_device_ids`, `notify_user_ids`)

#### RNF06 — Compatibilidade de Hardware
- RNF06.1: Firmware deve caber na flash ESP32 (CRÍTICO: não pode estourar capacidade da placa)
- RNF06.2: Preferir tipos de largura fixa no firmware (`uint8_t`, `uint16_t`)
- RNF06.3: Suporte a OTA via Wi-Fi para atualização de firmware em campo

## Related

[[regras-negocio]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]

#arquitetura #ruraltech 