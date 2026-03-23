(function() {
  'use strict';

  function statePayload(commandId, line) {
    const state = window.SoloCodeMonacoMain.state();
    return {
      pane: state.currentPane,
      path: state.currentPath,
      commandId: commandId,
      line: line || null
    };
  }

  function register(editor) {
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
      window.SoloCodeMonacoBridge.post('save', { path: window.SoloCodeMonacoMain.state().currentPath });
    });

    editor.addAction({
      id: 'solocode.commandPalette',
      label: 'Command Palette',
      keybindings: [monaco.KeyCode.F1],
      run: function() {
        editor.trigger('keyboard', 'editor.action.quickCommand', {});
      }
    });

    editor.addAction({
      id: 'solocode.fixInChat',
      label: 'Fix in Chat',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF],
      contextMenuGroupId: 'solocode',
      contextMenuOrder: 1,
      run: function(ed) {
        const state = window.SoloCodeMonacoMain.state();
        const line = (ed.getPosition() || {}).lineNumber || 1;
        const selection = window.SoloCodeMonacoBridge.selectedText(ed) || ed.getModel().getLineContent(line);
        window.SoloCodeMonacoBridge.post('fixInChat', {
          path: state.currentPath,
          selection: selection,
          line: line
        });
      }
    });

    editor.addAction({
      id: 'solocode.addToChat',
      label: 'Add to Chat',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyL],
      contextMenuGroupId: 'solocode',
      contextMenuOrder: 2,
      run: function(ed) {
        const state = window.SoloCodeMonacoMain.state();
        window.SoloCodeMonacoBridge.post('addToChat', {
          path: state.currentPath,
          selection: window.SoloCodeMonacoBridge.selectedText(ed),
          line: (ed.getPosition() || {}).lineNumber || 1
        });
      }
    });

    editor.addAction({
      id: 'solocode.quickOpen',
      label: 'Quick Open File',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyP],
      run: function() {
        window.SoloCodeMonacoBridge.post('actionInvoked', statePayload('quickOpen'));
      }
    });

    editor.addAction({
      id: 'solocode.toggleSplit',
      label: 'Toggle Split Editor',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.Backslash],
      run: function() {
        window.SoloCodeMonacoBridge.post('actionInvoked', statePayload('toggleSplit'));
      }
    });

    editor.addAction({
      id: 'solocode.showProblems',
      label: 'Show Problems',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyM],
      run: function() {
        window.SoloCodeMonacoBridge.post('actionInvoked', statePayload('showProblems'));
      }
    });

    editor.addAction({
      id: 'solocode.formatDocument',
      label: 'Format Document',
      keybindings: [monaco.KeyMod.Shift | monaco.KeyMod.Alt | monaco.KeyCode.KeyF],
      run: function() {
        window.SoloCodeMonacoBridge.post('actionInvoked', statePayload('formatDocument'));
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

  window.SoloCodeMonacoActions = {
    register: register,
    runCommand: runCommand
  };
})();
