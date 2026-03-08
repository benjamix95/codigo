(function() {
  'use strict';

  function statePayload(commandId, line) {
    const state = window.CodigoMonacoMain.state();
    return {
      pane: state.currentPane,
      path: state.currentPath,
      commandId: commandId,
      line: line || null
    };
  }

  function register(editor) {
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
      window.CodigoMonacoBridge.post('save', { path: window.CodigoMonacoMain.state().currentPath });
    });

    editor.addAction({
      id: 'codigo.commandPalette',
      label: 'Command Palette',
      keybindings: [monaco.KeyCode.F1],
      run: function() {
        editor.trigger('keyboard', 'editor.action.quickCommand', {});
      }
    });

    editor.addAction({
      id: 'codigo.fixInChat',
      label: 'Fix in Chat',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF],
      contextMenuGroupId: 'codigo',
      contextMenuOrder: 1,
      run: function(ed) {
        const state = window.CodigoMonacoMain.state();
        const line = (ed.getPosition() || {}).lineNumber || 1;
        const selection = window.CodigoMonacoBridge.selectedText(ed) || ed.getModel().getLineContent(line);
        window.CodigoMonacoBridge.post('fixInChat', {
          path: state.currentPath,
          selection: selection,
          line: line
        });
      }
    });

    editor.addAction({
      id: 'codigo.addToChat',
      label: 'Add to Chat',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyL],
      contextMenuGroupId: 'codigo',
      contextMenuOrder: 2,
      run: function(ed) {
        const state = window.CodigoMonacoMain.state();
        window.CodigoMonacoBridge.post('addToChat', {
          path: state.currentPath,
          selection: window.CodigoMonacoBridge.selectedText(ed),
          line: (ed.getPosition() || {}).lineNumber || 1
        });
      }
    });

    editor.addAction({
      id: 'codigo.quickOpen',
      label: 'Quick Open File',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyP],
      run: function() {
        window.CodigoMonacoBridge.post('actionInvoked', statePayload('quickOpen'));
      }
    });

    editor.addAction({
      id: 'codigo.toggleSplit',
      label: 'Toggle Split Editor',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.Backslash],
      run: function() {
        window.CodigoMonacoBridge.post('actionInvoked', statePayload('toggleSplit'));
      }
    });

    editor.addAction({
      id: 'codigo.showProblems',
      label: 'Show Problems',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyM],
      run: function() {
        window.CodigoMonacoBridge.post('actionInvoked', statePayload('showProblems'));
      }
    });

    editor.addAction({
      id: 'codigo.formatDocument',
      label: 'Format Document',
      keybindings: [monaco.KeyMod.Shift | monaco.KeyMod.Alt | monaco.KeyCode.KeyF],
      run: function() {
        window.CodigoMonacoBridge.post('actionInvoked', statePayload('formatDocument'));
      }
    });
  }

  function runCommand(editor, commandId) {
    switch (commandId) {
      case 'findInFile':
        editor.getAction('actions.find').run();
        break;
      case 'replaceInFile':
        editor.getAction('editor.action.startFindReplaceAction').run();
        break;
      case 'gotoLine':
        editor.getAction('editor.action.gotoLine').run();
        break;
      case 'showOutline':
        editor.getAction('editor.action.quickOutline').run();
        break;
      case 'showCommandPalette':
        editor.trigger('keyboard', 'editor.action.quickCommand', {});
        break;
      default:
        break;
    }
  }

  window.CodigoMonacoActions = {
    register: register,
    runCommand: runCommand
  };
})();
