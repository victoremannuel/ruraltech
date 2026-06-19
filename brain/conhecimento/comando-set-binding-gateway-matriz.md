# comando para gravar na coleira informações 

necessárias depois de limpar o firmware e regravar

O jeito mais simples de mandar essa informação para a matriz é **pela WebSocket local dela** [[fluxos-comunicacao-ponta-a-ponta]], não por HTTP POST.

Isso porque a matriz expõe `/status` por HTTP para consulta, mas os comandos entram pela **WebSocket na porta 81** [[visao-geral]]. O app faz exatamente isso: conecta na WebSocket do gateway e envia um JSON no formato `type: "send_command"` [[fluxo-comandos]].

**Conceitos relacionados:** [[gateway-matriz]] [[ruraltech]] [[modelagem-dados-supabase]] [[auditoria-comunicacao-v2.3.2]]

Vou te passar o caminho mais direto, usando só navegador e o console.

## Método mais prático: navegador + console

### 1. Conecte seu celular ou computador no Wi-Fi da matriz

No seu log, a matriz subiu este AP:

`RuralTech-Matriz-000000`

Conecte nele com a senha configurada no firmware da matriz.

### 2. Confirme que a matriz está viva

Abra o navegador e acesse:

```text id="am6qw7"
http://192.168.4.1/status
```

Se estiver tudo certo, vai abrir um JSON.

Procure estes campos:

* `bindingReady`
* `propertyId`
* `propertyScopeId`
* `matrixGatewayId`

No seu caso atual, deve aparecer `bindingReady` [[modelagem-dados-supabase]] como `false` ou equivalente.

### 3. Abra o console do navegador

No Mac:

* Safari: habilite “Desenvolvedor” e use `Option + Command + C`
* Chrome: `Command + Option + J`

### 4. Cole este código no console

Troque nada nos valores abaixo por enquanto, porque eles batem com o que você mostrou nos logs.

```javascript id="706j34"
const ws = new WebSocket('ws://192.168.4.1:81');

ws.onopen = () => {
  console.log('WS conectada. Enviando SET_BINDING...');
  ws.send(JSON.stringify({
    type: 'send_command',
    device_id: 0,
    command: 'SET_BINDING',
    payload: {
        property_id: "---id da fazenda---",
        property_scope_id: "---scope id da fazenda---",
        matrix_gateway_id: "---p do gateway---",
        binding_version: 1
    }
  }));
};

ws.onmessage = (event) => {
  console.log('Resposta da matriz:', event.data);
};

ws.onerror = (event) => {
  console.log('Erro WS:', event);
};

ws.onclose = () => {
  console.log('WS fechada');
};
```

### 5. Veja a resposta

Se der certo, a matriz deve responder pela própria WebSocket com um `command_result` parecido com isso:

```json id="ajhn6w"
{
  "type": "command_result",
  "ok": true,
  "command": "SET_BINDING",
  "supports_scoped_lora": true,
  "binding_ready": true,
  "property_id": "---id da fazenda---",
  "property_scope_id": "---scope id da fazenda---",
  "matrix_gateway_id": "---p do gateway---",
  "binding_version": 1
}
```

### 6. Confirme no `/status`

Depois disso, atualize:

```text id="n3jz7c"
http://192.168.4.1/status
```

Agora o esperado é aparecer algo assim:

* `bindingReady: true`
* `propertyId: "T0xeG8WQHwJRI6H3t7vr"`
* `propertyScopeId: "9FFFC95AA1624895"`
* `matrixGatewayId: "192.168.4.1"`

### 7. Veja o serial monitor da matriz

Depois de aplicar o binding, quando a coleira transmitir de novo, o `scope_reject ... ready=0` [[auditoria-comunicacao-v2.3.2]] deve sumir.

A sequência esperada passa a ser:

```text id="mz6c0f"
[I] LoRa RX aceito ...
[I] CLOUD_TX_BEGIN ...
[I] CLOUD_TX_STEP ... step=latest ...
[I] CLOUD_TX_STEP ... step=history ...
[I] CLOUD_TX_DONE ...
```

---

## Como saber se funcionou de verdade

Funcionou quando acontecerem estas 3 coisas:

1. `/status` mostrar `bindingReady = true`
2. o serial da matriz parar de mostrar `scope_reject ... ready=0`
3. começarem a aparecer os logs `CLOUD_TX_*` [[auditoria-comunicacao-v2.3.2]]

---

## Se a WebSocket não conectar

Se o console mostrar erro, faça este checklist:

1. confirme que você está conectado no Wi-Fi da matriz
2. abra `http://192.168.4.1/status`
3. se `/status` abrir, mas a WS falhar, teste recarregar a página e executar o script de novo
4. confira se a porta 81 não está bloqueada no navegador

---

## Observação importante

Não precisa reiniciar a matriz para o binding valer. O firmware salva isso na NVS e já atualiza o estado em memória na hora. Então, se o comando entrar com sucesso, a própria matriz já deve passar para `ready=1` sem reboot.

## Jeito alternativo

Também dá para mandar isso pelo próprio app, desde que ele esteja conectado na WebSocket da matriz (`ws://192.168.4.1:81`) e exista uma tela/caminho para comando genérico. Mas, para teste rápido e sem depender da UI do app, o console do navegador é o melhor caminho.
