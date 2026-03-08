(function() {
  'use strict';

  const pending = new Map();
  let nextRequestId = 1;

  function encodeBase64(value) {
    return btoa(unescape(encodeURIComponent(value || '')));
  }

  function decodeBase64(value) {
    return decodeURIComponent(escape(atob(value || '')));
  }

  function post(type, payload) {
    if (
      window.webkit &&
      window.webkit.messageHandlers &&
      window.webkit.messageHandlers.monacobridge
    ) {
      window.webkit.messageHandlers.monacobridge.postMessage({
        type: type,
        payload: payload || {}
      });
    }
  }

  function selectionPayload(editor) {
    const selection = editor.getSelection();
    if (!selection) {
      return {
        selectionStartLine: null,
        selectionStartColumn: null,
        selectionEndLine: null,
        selectionEndColumn: null
      };
    }
    return {
      selectionStartLine: selection.startLineNumber,
      selectionStartColumn: selection.startColumn,
      selectionEndLine: selection.endLineNumber,
      selectionEndColumn: selection.endColumn
    };
  }

  function requestContext(editor, pane, path, extra) {
    const model = editor.getModel();
    const position = editor.getPosition() || { lineNumber: 1, column: 1 };
    const wordInfo = model ? model.getWordAtPosition(position) : null;
    return Object.assign(
      {
        requestId: 'req-' + nextRequestId++,
        pane: pane || 'primary',
        path: path || '',
        word: wordInfo ? wordInfo.word : '',
        line: position.lineNumber,
        column: position.column
      },
      selectionPayload(editor),
      extra || {}
    );
  }

  function request(requestType, requestPayload) {
    const payload = requestPayload || {};
    const requestId = payload.requestId || ('req-' + nextRequestId++);
    payload.requestId = requestId;
    return new Promise(function(resolve) {
      pending.set(requestId, resolve);
      post('bridgeRequest', {
        requestType: requestType,
        request: payload
      });
    });
  }

  function resolveRequest(requestId, encodedPayload) {
    const resolver = pending.get(requestId);
    if (!resolver) return;
    pending.delete(requestId);
    if (!encodedPayload) {
      resolver(null);
      return;
    }
    try {
      resolver(JSON.parse(decodeBase64(encodedPayload)));
    } catch (error) {
      console.error('Failed to decode Monaco bridge payload', error);
      resolver(null);
    }
  }

  function selectedText(editor) {
    const selection = editor.getSelection();
    if (!selection) return '';
    return editor.getModel().getValueInRange(selection);
  }

  window.CodigoMonacoBridge = {
    decodeBase64: decodeBase64,
    encodeBase64: encodeBase64,
    post: post,
    request: request,
    requestContext: requestContext,
    resolveRequest: resolveRequest,
    selectedText: selectedText
  };

  window.monacoAPI = window.monacoAPI || {};
  window.monacoAPI.resolveRequest = resolveRequest;
})();
