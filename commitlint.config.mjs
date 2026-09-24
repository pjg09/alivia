// Valida que los mensajes sigan Conventional Commits. La convención está en
// CONTRIBUTING.md, y no es cosmética: el mensaje decide qué versión se publica.
//
//   npx commitlint --from HEAD~1 --to HEAD --verbose

export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'perf', 'refactor', 'docs', 'test', 'build', 'ci', 'chore', 'style', 'revert'],
    ],
    'scope-enum': [
      2,
      'always',
      ['db', 'catalogo', 'calendario', 'auth', 'avisos', 'pagos', 'api', 'web', 'infra', 'release'],
    ],
    // El ámbito es opcional, pero si se pone tiene que ser uno de la lista.
    'scope-empty': [0],
    'header-max-length': [2, 'always', 72],
    // La descripción va en español y en imperativo. El modo verbal no se puede
    // comprobar, pero sí que no termine en punto y que no empiece en mayúscula.
    // 'sentence-case' es el que detecta la mayúscula inicial: sin él, "Envía el
    // aviso" pasa, porque 'start-case' solo cubre "Envía El Aviso".
    'subject-full-stop': [2, 'never', '.'],
    'subject-case': [2, 'never', ['sentence-case', 'start-case', 'pascal-case', 'upper-case']],
    'body-max-line-length': [2, 'always', 100],
  },
};
