/**
 * MQ5 Input Parameter Parser
 *
 * Extracts `input` declarations from .mq5 source files.
 * Handles: input groups, int, double, bool, string, ENUM types.
 *
 * Example input:
 *   input group "=== Session Settings (GMT Hours) ==="
 *   input int    InpAsianEnd   = 8;    // Asian Session End Hour
 *   input double InpRiskReward = 1.5;  // Risk-to-Reward Ratio
 */

import type { StrategyInput } from '@algo-trading/shared';

// Re-export for convenience
export type { StrategyInput };

/**
 * Parse input parameters from MQ5 source code
 */
export function parseMq5Inputs(source: string): StrategyInput[] {
  const inputs: StrategyInput[] = [];
  let currentGroup = '';

  const lines = source.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();

    // Match group declaration: input group "=== Group Name ==="
    const groupMatch = trimmed.match(/^input\s+group\s+"[=\s]*([^"=]+?)[=\s]*"/);
    if (groupMatch) {
      currentGroup = groupMatch[1].trim();
      continue;
    }

    // Match input declaration:
    // input TYPE NAME = DEFAULT; // Comment
    const inputMatch = trimmed.match(
      /^input\s+(int|double|bool|string|ulong|ENUM_\w+)\s+(\w+)\s*=\s*([^;]+);(?:\s*\/\/\s*(.*))?/
    );

    if (inputMatch) {
      const [, rawType, name, rawDefault, comment] = inputMatch;

      // Skip magic number inputs — not optimization parameters
      if (name === 'InpMagicNumber' || name === 'InpMagic') continue;

      const type = normalizeType(rawType);
      const defaultValue = parseDefault(rawType, rawDefault.trim());
      const label = comment?.trim() || name;

      inputs.push({
        name,
        type,
        default: defaultValue,
        label,
        group: currentGroup,
        optimize: {
          enabled: false,
          min: 0,
          max: 0,
          step: 0,
        },
      });
    }
  }

  return inputs;
}

function normalizeType(rawType: string): 'int' | 'double' | 'bool' | 'string' | 'enum' {
  if (rawType === 'int' || rawType === 'ulong') return 'int';
  if (rawType === 'double') return 'double';
  if (rawType === 'bool') return 'bool';
  if (rawType === 'string') return 'string';
  if (rawType.startsWith('ENUM_')) return 'enum';
  return 'string';
}

function parseDefault(rawType: string, rawDefault: string): number | string | boolean {
  if (rawType === 'bool') {
    return rawDefault.toLowerCase() === 'true';
  }
  if (rawType === 'int' || rawType === 'ulong') {
    const parsed = parseInt(rawDefault, 10);
    if (isNaN(parsed)) {
      console.warn(`  Warning: Could not parse int default "${rawDefault}", using 0`);
      return 0;
    }
    return parsed;
  }
  if (rawType === 'double') {
    const parsed = parseFloat(rawDefault);
    if (isNaN(parsed)) {
      console.warn(`  Warning: Could not parse double default "${rawDefault}", using 0`);
      return 0;
    }
    return parsed;
  }
  if (rawType.startsWith('ENUM_')) {
    // For enums, store the enum value name as string
    return rawDefault;
  }
  // string type — remove quotes if present
  return rawDefault.replace(/^"(.*)"$/, '$1');
}
