# ruraltech

Monorepo com:
- `coleira/`: firmware ESP32 da coleira
- `gateway/`: firmware ESP32 do gateway
- `app/`: aplicativo Flutter + Firebase

## Apoio Git (commit/push/sync)

### Erro comum no push (HTTP 400)

Se aparecer algo como:

```text
error: RPC failed; HTTP 400 curl 22 The requested URL returned error: 400
send-pack: unexpected disconnect while reading sideband packet
fatal: the remote end hung up unexpectedly
Everything up-to-date
```

isso normalmente indica falha de transporte na conexão HTTP, e em alguns casos o commit pode já ter sido aplicado no remoto.

### 1) Confirmar se o push realmente chegou no remoto

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Se os hashes forem iguais, o conteúdo local já está em `origin/main`.

Comandos extras de conferência:

```bash
git status
git log --oneline -n 3
git log origin/main --oneline -n 3
```

### 2) Ajustes de estabilidade para push via HTTPS

```bash
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global core.compression 0
```

Depois, tente novamente:

```bash
git push origin main
```

### 3) Alternativa recomendada se HTTPS continuar falhando: SSH

```bash
git remote set-url origin git@github.com:victoremannuel/ruraltech.git
ssh -T git@github.com
git push origin main
```

### 4) Voltar configs opcionais depois de estabilizar

Se o push já estiver funcionando e você quiser limpar ajustes temporários:

```bash
git config --global --unset http.postBuffer
git config --global --unset core.compression
```

Sugestão: manter `http.version=HTTP/1.1` caso a rede continue instável para uploads maiores.
