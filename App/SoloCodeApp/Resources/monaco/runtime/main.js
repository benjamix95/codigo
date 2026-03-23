(function() {
  'use strict';

  const VS_BASE = new URL('./vs/', window.location.href).href;
  const state = {
    currentPane: 'primary',
    currentPath: '',
    isSettingValue: false,
    debounceTimer: null,
    models: new Map(),
    viewStates: new Map(),
    editor: null
  };

  self.MonacoEnvironment = {
    getWorkerUrl: function(moduleId, label) {
      const workerMap = {
        json: 'language/json/jsonWorker.js',
        css: 'language/css/cssWorker.js',
        scss: 'language/css/cssWorker.js',
        less: 'language/css/cssWorker.js',
        html: 'language/html/htmlWorker.js',
        handlebars: 'language/html/htmlWorker.js',
        razor: 'language/html/htmlWorker.js',
        typescript: 'language/typescript/tsWorker.js',
        javascript: 'language/typescript/tsWorker.js'
      };
      const path = workerMap[label] || 'base/worker/workerMain.js';
      return 'data:text/javascript;charset=utf-8,' + encodeURIComponent(
        'self.MonacoEnvironment = { baseUrl: "' + VS_BASE + '" };' +
        'importScripts("' + VS_BASE + path + '");'
      );
    }
  };

  require.config({ paths: { vs: VS_BASE.replace(/\/$/, '') } });

  function currentModel() {
    return state.editor ? state.editor.getModel() : null;
  }

  function notifyMarkers() {
    const model = currentModel();
    if (!model) return;
    const markers = monaco.editor.getModelMarkers({ resource: model.uri }).map(function(marker) {
      return {
        message: marker.message,
        severity: marker.severity,
        source: marker.source || 'monaco',
        startLineNumber: marker.startLineNumber,
        startColumn: marker.startColumn,
        endLineNumber: marker.endLineNumber,
        endColumn: marker.endColumn
      };
    });
    window.SoloCodeMonacoBridge.post('markersChanged', {
      path: state.currentPath,
      markers: markers
    });
  }

  function ensureModel(path, content) {
    const key = path || ('inmemory://' + state.currentPane);
    let model = state.models.get(key);
    if (!model) {
      model = monaco.editor.createModel(
        content || '',
        window.SoloCodeMonacoLang.langForPath(path),
        window.SoloCodeMonacoLang.uriForPath(path, state.currentPane)
      );
      state.models.set(key, model);
    } else if (typeof content === 'string' && model.getValue() !== content) {
      model.setValue(content);
    }
    monaco.editor.setModelLanguage(model, window.SoloCodeMonacoLang.langForPath(path));
    return model;
  }

  function switchModel(path, content) {
    const previousPath = state.currentPath || ('inmemory://' + state.currentPane);
    if (state.editor) {
      state.viewStates.set(previousPath, state.editor.saveViewState());
    }
    state.currentPath = path || '';
    const model = ensureModel(path, content);
    state.editor.setModel(model);
    const nextKey = path || ('inmemory://' + state.currentPane);
    const savedState = state.viewStates.get(nextKey);
    if (savedState) {
      state.editor.restoreViewState(savedState);
    }
    state.editor.focus();
    notifyMarkers();
  }

  require(['vs/editor/editor.main'], function() {
    window.SoloCodeMonacoThemes.register(monaco);
    window.SoloCodeMonacoProviders.register(monaco);

    state.editor = monaco.editor.create(document.getElementById('container'), {
      value: '',
      language: 'plaintext',
      theme: 'solocode-dark',
      minimap: { enabled: true, renderCharacters: false, scale: 1 },
      lineNumbers: 'on',
      wordWrap: 'off',
      tabSize: 4,
      insertSpaces: true,
      fontSize: 13,
      lineHeight: 20,
      fontFamily: "'JetBrains Mono', 'SF Mono', Menlo, Monaco, monospace",
      scrollBeyondLastLine: false,
      automaticLayout: true,
      renderWhitespace: 'selection',
      bracketPairColorization: { enabled: true },
      guides: { bracketPairs: true, indentation: true },
      smoothScrolling: true,
      cursorBlinking: 'smooth',
      cursorSmoothCaretAnimation: 'on',
      roundedSelection: true,
      padding: { top: 8, bottom: 8 },
      scrollbar: { verticalScrollbarSize: 10, horizontalScrollbarSize: 10, useShadows: false },
      suggestOnTriggerCharacters: true,
      quickSuggestions: true,
      folding: true,
      colorDecorators: true,
      stickyScroll: { enabled: true }
    });

    window.SoloCodeMonacoActions.register(state.editor);

    state.editor.onDidChangeModelContent(function() {
      if (state.isSettingValue) return;
      clearTimeout(state.debounceTimer);
      state.debounceTimer = setTimeout(function() {
        window.SoloCodeMonacoBridge.post('contentChanged', {
          pane: state.currentPane,
          path: state.currentPath,
          content: window.SoloCodeMonacoBridge.encodeBase64(state.editor.getValue())
        });
      }, 180);
    });

    state.editor.onDidChangeCursorPosition(function(event) {
      window.SoloCodeMonacoBridge.post('cursorChanged', {
        pane: state.currentPane,
        line: event.position.lineNumber,
        column: event.position.column
      });
    });

    state.editor.onDidChangeCursorSelection(function(event) {
      const selection = event.selection;
      window.SoloCodeMonacoBridge.post('selectionChanged', {
        pane: state.currentPane,
        startLine: selection.startLineNumber,
        startColumn: selection.startColumn,
        endLine: selection.endLineNumber,
        endColumn: selection.endColumn
      });
    });

    monaco.editor.onDidChangeMarkers(function(resources) {
      const model = currentModel();
      if (!model) return;
      const target = model.uri.toString();
      if (resources.some(function(resource) { return resource.toString() === target; })) {
        notifyMarkers();
      }
    });

    window.monacoAPI = Object.assign(window.monacoAPI || {}, {
      setPane: function(pane) {
        state.currentPane = pane || 'primary';
      },
      setValue: function(base64Content, filePath) {
        state.isSettingValue = true;
        switchModel(filePath, window.SoloCodeMonacoBridge.decodeBase64(base64Content));
        state.isSettingValue = false;
      },
      setTheme: function(themeName) {
        monaco.editor.setTheme(themeName);
      },
      setFontSize: function(size) {
        state.editor.updateOptions({ fontSize: size });
      },
      setFontFamily: function(family) {
        state.editor.updateOptions({ fontFamily: family });
      },
      setReadOnly: function(readOnly) {
        state.editor.updateOptions({ readOnly: !!readOnly });
      },
      applyDiagnostics: function(base64Payload, filePath) {
        const payload = JSON.parse(window.SoloCodeMonacoBridge.decodeBase64(base64Payload));
        const model = ensureModel(filePath, null);
        const markers = (payload.markers || []).map(function(marker) {
          return {
            message: marker.message,
            severity: marker.severity,
            source: marker.source,
            startLineNumber: marker.startLineNumber,
            startColumn: marker.startColumn,
            endLineNumber: marker.endLineNumber,
            endColumn: marker.endColumn
          };
        });
        monaco.editor.setModelMarkers(model, 'solocode', markers);
        notifyMarkers();
      },
      setWordWrap: function(wrap) {
        state.editor.updateOptions({ wordWrap: wrap ? 'on' : 'off' });
      },
      setMinimap: function(enabled) {
        state.editor.updateOptions({ minimap: { enabled: !!enabled } });
      },
      revealLine: function(line) {
        state.editor.revealLineInCenter(line);
      },
      focus: function() {
        state.editor.focus();
      },
      runCommand: function(commandId) {
        window.SoloCodeMonacoActions.runCommand(state.editor, commandId);
      },
      getContent: function() {
        return window.SoloCodeMonacoBridge.encodeBase64(state.editor.getValue());
      }
    });

    window.SoloCodeMonacoMain = {
      editor: function() { return state.editor; },
      state: function() { return state; }
    };

    window.SoloCodeMonacoBridge.post('ready', {});
  });
})();
