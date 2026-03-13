/**
 * Result Parser
 * Collects and parses optimization results from MT5 agent sandbox directories.
 *
 * After optimization, each agent writes opt_results.csv to its own MQL5/Files/ dir.
 * Format: profit,profitFactor,expectedPayoff,recoveryFactor,sharpeRatio,drawdownPercent,trades,customCriterion,param1=val1,param2=val2,...
 */

import * as fs from 'fs';
import * as path from 'path';
import type { OptimizationPass, JobResultSummary } from '@algo-trading/shared';

const RESULT_FILENAME = 'opt_results.csv';

/**
 * Find all agent result files in the Tester directory
 */
export function findResultFiles(mt5Path: string): string[] {
  const testerDir = path.join(mt5Path, 'Tester');
  const files: string[] = [];

  if (!fs.existsSync(testerDir)) return files;

  const entries = fs.readdirSync(testerDir);

  for (const entry of entries) {
    if (!entry.startsWith('Agent-')) continue;

    const resultPath = path.join(testerDir, entry, 'MQL5', 'Files', RESULT_FILENAME);
    if (fs.existsSync(resultPath)) {
      files.push(resultPath);
    }
  }

  return files;
}

/**
 * Parse all result files and return optimization passes
 */
export function parseResults(mt5Path: string): OptimizationPass[] {
  const files = findResultFiles(mt5Path);
  const passes: OptimizationPass[] = [];

  for (const filePath of files) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.trim().split('\n');

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;

        const pass = parseLine(trimmed);
        if (pass) passes.push(pass);
      }
    } catch (err) {
      console.warn(`Failed to parse result file ${filePath}:`, err);
    }
  }

  return passes;
}

/**
 * Parse a single CSV result line
 */
function parseLine(line: string): OptimizationPass | null {
  try {
    // Split on comma, but input params are in key=value format
    const parts = line.split(',');

    if (parts.length < 8) return null;

    const profit = parseFloat(parts[0]);
    const profitFactor = parseFloat(parts[1]);
    const expectedPayoff = parseFloat(parts[2]);
    const recoveryFactor = parseFloat(parts[3]);
    const sharpeRatio = parseFloat(parts[4]);
    const drawdownPercent = parseFloat(parts[5]);
    const trades = parseInt(parts[6], 10);
    const customCriterion = parseFloat(parts[7]);

    // Parse input parameters (key=value pairs)
    const inputs: Record<string, number | string | boolean> = {};
    for (let i = 8; i < parts.length; i++) {
      const eqIdx = parts[i].indexOf('=');
      if (eqIdx > 0) {
        const key = parts[i].substring(0, eqIdx);
        const val = parts[i].substring(eqIdx + 1);

        // Try to parse as number
        const num = Number(val);
        inputs[key] = isNaN(num) ? val : num;
      }
    }

    return {
      profit,
      profitFactor,
      expectedPayoff,
      recoveryFactor,
      sharpeRatio,
      drawdownPercent,
      trades,
      customCriterion,
      inputs,
    };
  } catch {
    return null;
  }
}

/**
 * Compute result summary from passes
 */
export function computeSummary(passes: OptimizationPass[]): JobResultSummary {
  let bestProfit = 0;
  let bestProfitFactor = 0;
  let bestCustomCriterion = 0;
  let bestDrawdown = 100;

  for (const pass of passes) {
    if (pass.profit > bestProfit) bestProfit = pass.profit;
    if (pass.profitFactor > bestProfitFactor) bestProfitFactor = pass.profitFactor;
    if (pass.customCriterion > bestCustomCriterion) bestCustomCriterion = pass.customCriterion;
    if (pass.drawdownPercent < bestDrawdown) bestDrawdown = pass.drawdownPercent;
  }

  return {
    totalPasses: passes.length,
    profitablePasses: passes.filter(p => p.profit > 0).length,
    bestProfit,
    bestProfitFactor,
    bestCustomCriterion,
    bestDrawdown,
  };
}

/**
 * Clean up result files from agent directories
 */
export function cleanupResults(mt5Path: string): void {
  const files = findResultFiles(mt5Path);
  for (const filePath of files) {
    try {
      fs.unlinkSync(filePath);
    } catch (err) {
      console.warn(`Failed to delete ${filePath}:`, err);
    }
  }
}
