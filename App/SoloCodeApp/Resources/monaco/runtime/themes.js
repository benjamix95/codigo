(function() {
  'use strict';

  function register(monacoInstance) {
    monacoInstance.editor.defineTheme('solocode-dark', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '6A737D', fontStyle: 'italic' },
        { token: 'keyword', foreground: 'C586C0' },
        { token: 'string', foreground: 'CE9178' },
        { token: 'number', foreground: 'B5CEA8' },
        { token: 'type', foreground: '4EC9B0' },
        { token: 'function', foreground: 'DCDCAA' },
        { token: 'variable', foreground: '9CDCFE' }
      ],
      colors: {
        'editor.background': '#111113',
        'editor.foreground': '#d4d4d4',
        'editor.lineHighlightBackground': '#ffffff08',
        'editor.selectionBackground': '#264f78',
        'editorLineNumber.foreground': '#555558',
        'editorLineNumber.activeForeground': '#c6c6c6',
        'editorCursor.foreground': '#aeafad',
        'editorIndentGuide.background': '#ffffff10',
        'editorIndentGuide.activeBackground': '#ffffff30',
        'editorGutter.background': '#111113',
        'editorWidget.background': '#1a1a1b',
        'editorSuggestWidget.background': '#1a1a1b',
        'editorHoverWidget.background': '#1a1a1b',
        'scrollbarSlider.background': '#ffffff15',
        'scrollbarSlider.hoverBackground': '#ffffff25',
        'scrollbarSlider.activeBackground': '#ffffff35'
      }
    });

    monacoInstance.editor.defineTheme('solocode-light', {
      base: 'vs',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '6A737D', fontStyle: 'italic' },
        { token: 'keyword', foreground: 'AF00DB' },
        { token: 'string', foreground: 'A31515' },
        { token: 'number', foreground: '098658' },
        { token: 'type', foreground: '267F99' }
      ],
      colors: {
        'editor.background': '#f8f8fa',
        'editor.foreground': '#1e1e1e',
        'editor.lineHighlightBackground': '#00000008',
        'editorLineNumber.foreground': '#b0b0b0',
        'editorLineNumber.activeForeground': '#333333',
        'editorGutter.background': '#f8f8fa'
      }
    });
  }

  window.SoloCodeMonacoThemes = { register: register };
})();
