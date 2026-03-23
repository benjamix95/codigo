(function() {
  'use strict';

  let providersRegistered = false;

  function monacoRange(line, column, endColumn) {
    return new monaco.Range(line, column, line, endColumn);
  }

  function provideRequest(editor) {
    const state = window.SoloCodeMonacoMain.state();
    return window.SoloCodeMonacoBridge.requestContext(editor, state.currentPane, state.currentPath);
  }

  function register(monacoInstance) {
    if (providersRegistered) return;
    providersRegistered = true;

    monacoInstance.languages.registerHoverProvider('swift', {
      provideHover: async function(model, position) {
        const request = provideRequest(window.SoloCodeMonacoMain.editor());
        request.line = position.lineNumber;
        request.column = position.column;
        request.word = (model.getWordAtPosition(position) || {}).word || '';
        if (!request.word) return null;
        const payload = await window.SoloCodeMonacoBridge.request('hoverRequested', request);
        if (!payload || !payload.contents) return null;
        return {
          range: window.SoloCodeMonacoLang.wordRange(model, position, request.word),
          contents: [{ value: payload.contents }]
        };
      }
    });

    monacoInstance.languages.registerDefinitionProvider('swift', {
      provideDefinition: async function(model, position) {
        const request = provideRequest(window.SoloCodeMonacoMain.editor());
        request.line = position.lineNumber;
        request.column = position.column;
        request.word = (model.getWordAtPosition(position) || {}).word || '';
        if (!request.word) return [];
        const payload = await window.SoloCodeMonacoBridge.request('definitionRequested', request);
        if (!payload || !payload.locations) return [];
        return payload.locations.map(function(location) {
          return {
            uri: window.SoloCodeMonacoLang.uriForPath(location.filePath, request.pane),
            range: monacoRange(location.line, location.column, location.column + Math.max(1, location.symbolName.length))
          };
        });
      }
    });

    monacoInstance.languages.registerReferenceProvider('swift', {
      provideReferences: async function(model, position) {
        const request = provideRequest(window.SoloCodeMonacoMain.editor());
        request.line = position.lineNumber;
        request.column = position.column;
        request.word = (model.getWordAtPosition(position) || {}).word || '';
        if (!request.word) return [];
        const payload = await window.SoloCodeMonacoBridge.request('referencesRequested', request);
        if (!payload || !payload.locations) return [];
        return payload.locations.map(function(location) {
          return {
            uri: window.SoloCodeMonacoLang.uriForPath(location.filePath, request.pane),
            range: monacoRange(location.line, location.column, location.column + Math.max(1, location.symbolName.length))
          };
        });
      }
    });

    monacoInstance.languages.registerRenameProvider('swift', {
      provideRenameEdits: async function(model, position, newName) {
        const request = provideRequest(window.SoloCodeMonacoMain.editor());
        request.line = position.lineNumber;
        request.column = position.column;
        request.word = (model.getWordAtPosition(position) || {}).word || '';
        request.newName = newName;
        if (!request.word || !newName) return { edits: [] };
        const payload = await window.SoloCodeMonacoBridge.request('renameRequested', request);
        if (!payload || !payload.edits) return { edits: [] };
        return {
          edits: payload.edits.map(function(edit) {
            return {
              resource: window.SoloCodeMonacoLang.uriForPath(edit.filePath, request.pane),
              edit: {
                range: monacoRange(edit.line, edit.column, edit.endColumn),
                text: edit.text
              }
            };
          })
        };
      }
    });

    monacoInstance.languages.registerDocumentSymbolProvider('swift', {
      provideDocumentSymbols: async function(model) {
        const request = provideRequest(window.SoloCodeMonacoMain.editor());
        const payload = await window.SoloCodeMonacoBridge.request('outlineRequested', request);
        if (!payload || !payload.symbols) return [];
        return payload.symbols.map(function(symbol) {
          return {
            name: symbol.name,
            kind: monaco.languages.SymbolKind.Function,
            location: {
              uri: model.uri,
              range: monacoRange(symbol.line, Math.max(1, symbol.column), Math.max(2, symbol.column + 1))
            }
          };
        });
      }
    });
  }

  window.SoloCodeMonacoProviders = { register: register };
})();
