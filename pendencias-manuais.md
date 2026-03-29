# Pendências manuais para concluir o fix de arrebanhamento

Este ajuste alterou regras do Firestore e o comportamento do mapa no app. Para funcionar em ambiente real (Firebase/prod), siga este passo a passo.

## 1) Publicar regras do Firestore atualizadas

1. Abra um terminal na raiz do projeto.
2. Entre na pasta do app:
   ```bash
   cd app
   ```
3. Faça login no Firebase CLI (se ainda não estiver autenticado):
   ```bash
   firebase login
   ```
4. Selecione o projeto correto:
   ```bash
   firebase use <seu-project-id>
   ```
5. Publique as regras do Firestore:
   ```bash
   firebase deploy --only firestore:rules
   ```

## 2) Validar o fluxo de arrebanhamento no app (teste manual)

1. Abra o app com um usuário que tenha acesso às coleiras/propriedade.
2. Vá em **Incluir > Solicitar arrebanhamento** (ou pela tela de **Comandos da coleira**).
3. Dê zoom no mapa (pinça).
4. Toque no mapa para adicionar vários pontos do polígono.
5. Confirme que o zoom **não é resetado** ao adicionar cada ponto.
6. Selecione uma ou mais coleiras e envie a solicitação.
7. Confirme que não ocorre mais `permission-denied` na criação da operação.

## 3) (Opcional) Revalidar suite local antes de subir produção

Na raiz do projeto:

```bash
cd app && flutter analyze && flutter test
cd /workspace/ruraltech/app/rules-tests && npm test
```

