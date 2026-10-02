'use strict';

const vscode = require('vscode');
const { openResource } = require('./launcher');

function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand('paneharbor.open', async (resource) => {
    // Explorer's first argument is the right-click target, including in a multi-selection.
    const target = resource instanceof vscode.Uri ? resource : vscode.window.activeTextEditor?.document.uri;
    try {
      const appPath = vscode.workspace.getConfiguration('paneharbor').get('applicationPath');
      await openResource(target, appPath);
    } catch (error) {
      await vscode.window.showErrorMessage(`PaneHarbor: ${error.message}`);
    }
  }));
}

module.exports = { activate, deactivate() {} };
