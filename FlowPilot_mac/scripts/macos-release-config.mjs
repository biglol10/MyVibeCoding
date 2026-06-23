const developerIdEnvNames = ["FLOWPILOT_DEVELOPER_ID", "APPLE_DEVELOPER_IDENTITY"];
const notaryProfileEnvNames = ["APPLE_NOTARY_KEYCHAIN_PROFILE", "FLOWPILOT_NOTARY_KEYCHAIN_PROFILE"];

function firstEnvValue(env, names) {
  for (const name of names) {
    const value = env[name]?.trim();
    if (value) {
      return value;
    }
  }
  return "";
}

export function resolveDeveloperId(env, identitiesOutput = "") {
  const identity = firstEnvValue(env, developerIdEnvNames);

  if (!identity) {
    throw new Error(
      "FLOWPILOT_DEVELOPER_ID is required for release builds. Use a Developer ID Application identity.",
    );
  }

  if (!identity.startsWith("Developer ID Application:")) {
    throw new Error(
      `macOS release builds must use a Developer ID Application identity. Received: ${identity}`,
    );
  }

  if (identitiesOutput && !identitiesOutput.includes(`"${identity}"`)) {
    throw new Error(
      `${identity} is not installed in the current keychain. Install the Developer ID Application certificate first.`,
    );
  }

  return identity;
}

export function resolveNotaryArgs(env) {
  const keychainProfile = firstEnvValue(env, notaryProfileEnvNames);
  if (keychainProfile) {
    return {
      description: `keychain profile ${keychainProfile}`,
      args: ["--keychain-profile", keychainProfile],
    };
  }

  const appleId = env.APPLE_ID?.trim();
  const teamId = env.APPLE_TEAM_ID?.trim();
  const password = env.APPLE_APP_SPECIFIC_PASSWORD?.trim();
  if (appleId && teamId && password) {
    return {
      description: `Apple ID ${appleId} / team ${teamId}`,
      args: ["--apple-id", appleId, "--team-id", teamId, "--password", password],
    };
  }

  const apiKey = env.APP_STORE_CONNECT_API_KEY?.trim();
  const apiKeyId = env.APP_STORE_CONNECT_API_KEY_ID?.trim();
  const apiIssuer = env.APP_STORE_CONNECT_API_ISSUER?.trim();
  if (apiKey && apiKeyId && apiIssuer) {
    return {
      description: `App Store Connect API key ${apiKeyId}`,
      args: ["--key", apiKey, "--key-id", apiKeyId, "--issuer", apiIssuer],
    };
  }

  throw new Error(
    "Apple notarization credentials are required for release builds. Set APPLE_NOTARY_KEYCHAIN_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD.",
  );
}
