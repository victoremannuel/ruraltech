# Firebase Rules Tests

Suíte para validar:
1. Regras de acesso do Firestore por papel/vínculo.
2. Regras do RTDB para writer da matriz (`matrixId` + `writerKey`).

## Executar localmente

```bash
cd /Users/victor/Downloads/code/ruraltech/app/rules-tests
npm install
npm test
```

O `npm test` usa `firebase emulators:exec` para subir Firestore/RTDB emuladores
temporariamente e executar os testes Node.
