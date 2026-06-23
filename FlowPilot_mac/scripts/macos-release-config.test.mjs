import assert from "node:assert/strict";
import test from "node:test";

import { resolveDeveloperId, resolveNotaryArgs } from "./macos-release-config.mjs";

const identities = `
  1) ABCDEF1234567890 "Developer ID Application: FlowPilot Inc. (TEAM123456)"
  2) FEDCBA0987654321 "Apple Development: FlowPilot Inc. (TEAM123456)"
`;

test("requires a Developer ID Application signing identity for release builds", () => {
  assert.throws(
    () =>
      resolveDeveloperId(
        { FLOWPILOT_DEVELOPER_ID: "Apple Development: FlowPilot Inc. (TEAM123456)" },
        identities,
      ),
    /Developer ID Application/,
  );
});

test("rejects Developer ID identities that are not installed in the keychain", () => {
  assert.throws(
    () =>
      resolveDeveloperId(
        { FLOWPILOT_DEVELOPER_ID: "Developer ID Application: Missing Cert (TEAM123456)" },
        identities,
      ),
    /not installed/,
  );
});

test("resolves an installed Developer ID Application identity", () => {
  assert.equal(
    resolveDeveloperId(
      { FLOWPILOT_DEVELOPER_ID: "Developer ID Application: FlowPilot Inc. (TEAM123456)" },
      identities,
    ),
    "Developer ID Application: FlowPilot Inc. (TEAM123456)",
  );
});

test("prefers a notarytool keychain profile for notarization", () => {
  assert.deepEqual(resolveNotaryArgs({ APPLE_NOTARY_KEYCHAIN_PROFILE: "flowpilot-notary" }), {
    description: "keychain profile flowpilot-notary",
    args: ["--keychain-profile", "flowpilot-notary"],
  });
});

test("supports Apple ID notarization credentials when no keychain profile is provided", () => {
  assert.deepEqual(
    resolveNotaryArgs({
      APPLE_ID: "dev@example.com",
      APPLE_TEAM_ID: "TEAM123456",
      APPLE_APP_SPECIFIC_PASSWORD: "app-password",
    }),
    {
      description: "Apple ID dev@example.com / team TEAM123456",
      args: [
        "--apple-id",
        "dev@example.com",
        "--team-id",
        "TEAM123456",
        "--password",
        "app-password",
      ],
    },
  );
});

test("requires notarization credentials for release builds", () => {
  assert.throws(() => resolveNotaryArgs({}), /notarization credentials/);
});
