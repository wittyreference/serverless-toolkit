import { EnvironmentVariables } from '@twilio-labs/serverless-api';
import { stripIndent } from 'common-tags';
import dotenv from 'dotenv';
import path from 'path';
import { EnvironmentVariablesWithAuth } from '../../types/generic';
import { fileExists, readFile } from '../../utils/fs';

export async function readLocalEnvFile(flags: {
  cwd?: string;
  env?: string;
  loadSystemEnv?: boolean;
}): Promise<{ localEnv: EnvironmentVariablesWithAuth; envPath: string }> {
  if (flags.loadSystemEnv && typeof flags.env === 'undefined') {
    throw new Error(stripIndent`
      If you are using --load-system-env you'll also have to supply a --env flag.
      
      The .env file you are pointing at will be used to primarily load environment variables.
      Any empty entries in the .env file will fall back to the system's environment variables.
    `);
  }

  if (flags.cwd) {
    const envPath = path.resolve(flags.cwd, flags.env || '.env');

    let contentEnvFile;
    if (await fileExists(envPath)) {
      contentEnvFile = await readFile(envPath, 'utf8');
    } else if (flags.env) {
      throw new Error(`Failed to find .env file at "${envPath}"`);
    } else {
      contentEnvFile = '';
    }

    let localEnv;
    try {
      localEnv = dotenv.parse(contentEnvFile);
    } catch (err) {
      throw new Error('Failed to parse .env file');
    }

    if (flags.loadSystemEnv && typeof flags.env !== 'undefined') {
      for (const key of Object.keys(localEnv)) {
        const systemValue = process.env[key];
        if (systemValue) {
          localEnv[key] = localEnv[key] || systemValue;
        }
      }
    }

    return { localEnv, envPath };
  }
  return { envPath: '', localEnv: {} };
}

// Twilio Serverless environment context has a hard limit of 3583 bytes.
// This threshold triggers a warning before the deploy fails with error 82006.
const ENV_CONTEXT_WARN_BYTES = 3000;
const ENV_CONTEXT_MAX_BYTES = 3583;

export function filterEnvVariablesForDeploy(
  localEnv: EnvironmentVariablesWithAuth
): EnvironmentVariables {
  const env = {
    ...localEnv,
  };

  for (let key of Object.keys(env)) {
    const val = env[key];
    if (typeof val === 'string' && val.length === 0) {
      delete env[key];
    }
  }

  delete env.ACCOUNT_SID;
  delete env.AUTH_TOKEN;

  checkEnvContextSize(env);

  return env;
}

function checkEnvContextSize(env: EnvironmentVariables): void {
  const size = Buffer.byteLength(JSON.stringify(env), 'utf8');
  if (size > ENV_CONTEXT_MAX_BYTES) {
    console.warn(
      `\n  WARNING: Environment variables total ${size} bytes, exceeding the ${ENV_CONTEXT_MAX_BYTES}-byte Twilio Serverless context limit.\n` +
        `  Deploy will fail with error 82006. Remove unused variables from .env or split across services.\n`
    );
  } else if (size > ENV_CONTEXT_WARN_BYTES) {
    console.warn(
      `\n  WARNING: Environment variables total ${size}/${ENV_CONTEXT_MAX_BYTES} bytes (${Math.round(
        (size / ENV_CONTEXT_MAX_BYTES) * 100
      )}% of limit).\n` +
        `  Consider removing unused variables to avoid error 82006.\n`
    );
  }
}
