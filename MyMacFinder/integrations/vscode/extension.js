'use strict';

const vscode = require('vscode');
const { openResource } = require('./launcher');

function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand('mymacfinder.open', async (resource) => {
    // Explorer's first argument is the right-click target, including in a multi-selection.
    const target = resource instanceof vscode.Uri ? resource : vscode.window.activeTextEditor?.document.uri;
    try {
      const appPath = vscode.workspace.getConfiguration('mymacfinder').get('applicationPath');
      await openResource(target, appPath);
    } catch (error) {
      await vscode.window.showErrorMessage(`MyMacFinder: ${error.message}`);
    }
  }));
}

module.exports = { activate, deactivate() {} };
