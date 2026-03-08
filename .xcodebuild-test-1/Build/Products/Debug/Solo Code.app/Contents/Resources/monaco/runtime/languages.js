(function() {
  'use strict';

  const EXT_TO_LANG = {
    swift: 'swift',
    py: 'python',
    pyw: 'python',
    js: 'javascript',
    jsx: 'javascript',
    ts: 'typescript',
    tsx: 'typescript',
    json: 'json',
    jsonc: 'json',
    md: 'markdown',
    mdx: 'mdx',
    html: 'html',
    htm: 'html',
    css: 'css',
    scss: 'scss',
    less: 'less',
    rs: 'rust',
    go: 'go',
    java: 'java',
    kt: 'kotlin',
    kts: 'kotlin',
    c: 'c',
    h: 'c',
    cpp: 'cpp',
    cc: 'cpp',
    cxx: 'cpp',
    hpp: 'cpp',
    rb: 'ruby',
    sh: 'shell',
    bash: 'shell',
    zsh: 'shell',
    fish: 'shell',
    yml: 'yaml',
    yaml: 'yaml',
    toml: 'ini',
    xml: 'xml',
    svg: 'xml',
    sql: 'sql',
    graphql: 'graphql',
    gql: 'graphql',
    proto: 'protobuf',
    lua: 'lua',
    r: 'r',
    pl: 'perl',
    php: 'php',
    dart: 'dart',
    txt: 'plaintext',
    log: 'plaintext',
    csv: 'plaintext',
    env: 'ini',
    gitignore: 'ini',
    editorconfig: 'ini',
    plist: 'xml',
    xcconfig: 'ini',
    pbxproj: 'ini'
  };

  function langForPath(path) {
    if (!path) return 'plaintext';
    const base = path.split('/').pop() || '';
    if (base === 'Dockerfile' || base.indexOf('Dockerfile.') === 0) return 'dockerfile';
    if (base === 'Makefile' || base === 'GNUmakefile') return 'plaintext';
    if (base === 'Package.swift') return 'swift';
    const ext = base.indexOf('.') >= 0 ? base.split('.').pop().toLowerCase() : '';
    return EXT_TO_LANG[ext] || 'plaintext';
  }

  function uriForPath(path, pane) {
    if (path) return monaco.Uri.file(path);
    return monaco.Uri.parse('inmemory://codigo/' + (pane || 'primary'));
  }

  function wordRange(model, position, fallbackWord) {
    const info = model.getWordAtPosition(position);
    if (info) {
      return new monaco.Range(
        position.lineNumber,
        info.startColumn,
        position.lineNumber,
        info.endColumn
      );
    }
    const word = fallbackWord || '';
    return new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column + word.length);
  }

  window.CodigoMonacoLang = {
    langForPath: langForPath,
    uriForPath: uriForPath,
    wordRange: wordRange
  };
})();
