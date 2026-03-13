/**
 * Generate MT5 .ini and .set configuration files for optimization jobs.
 * .set files must be UTF-16LE encoded for MT5.
 */

import * as fs from 'fs';
import * as path from 'path';
import { TIMEFRAME_TO_MT5_PERIOD } from '@algo-trading/shared';
import type { OptimizationJob, StrategyInput, InputOverride, SymbolMapping } from '@algo-trading/shared';

/**
 * Translate canonical symbol name to broker symbol using worker's mapping
 */
export function translateSymbol(canonical: string, mapping: SymbolMapping): string {
  // Check overrides first
  if (mapping.overrides && mapping.overrides[canonical]) {
    return mapping.overrides[canonical];
  }
  // Apply prefix/suffix
  return `${mapping.prefix || ''}${canonical}${mapping.suffix || ''}`;
}

/**
 * Generate .ini file content for MT5 strategy tester
 */
export function generateIniContent(
  job: OptimizationJob,
  brokerSymbol: string,
  eaFileName: string,
  setFileName: string,
  currency: string = 'USD',
): string {
  const period = TIMEFRAME_TO_MT5_PERIOD[job.timeframe];
  if (period === undefined) {
    console.warn(`Unknown timeframe "${job.timeframe}", falling back to M15 (period=15)`);
  }

  const lines = [
    '[Tester]',
    `Expert=${eaFileName}`,
    `ExpertParameters=${setFileName}`,
    `Symbol=${brokerSymbol}`,
    `Period=${period ?? 15}`,
    `Optimization=${job.optimizationMode}`,
    `Model=${job.model}`,
    `OptimizationCriterion=${job.optimizationCriterion}`,
    `FromDate=${job.fromDate}`,
    `ToDate=${job.toDate}`,
    `Deposit=${job.deposit}`,
    `Leverage=${job.leverage}`,
    `Currency=${currency}`,
    `ForwardMode=0`,
    `ShutdownTerminal=1`,
    `ReplaceReport=1`,
    `UseLocal=1`,
    `UseRemote=0`,
    `UseCloud=0`,
    `Visual=0`,
  ];

  return lines.join('\r\n') + '\r\n';
}

/**
 * Generate .set file content for MT5 strategy inputs
 * Format: ParamName=value||start||step||stop||Y/N
 * Must be written as UTF-16LE
 */
export function generateSetContent(
  inputs: StrategyInput[],
  overrides: Record<string, InputOverride>,
): string {
  const lines: string[] = [];

  for (const input of inputs) {
    const override = overrides[input.name];
    const defaultVal = String(input.default);

    if (override && override.enabled) {
      // Optimization enabled for this parameter
      lines.push(
        `${input.name}=${defaultVal}||${override.min}||${override.step}||${override.max}||Y`
      );
    } else {
      // Fixed value, no optimization
      lines.push(
        `${input.name}=${defaultVal}||0||0||0||N`
      );
    }
  }

  return lines.join('\r\n') + '\r\n';
}

/**
 * Write .ini file to disk
 */
export function writeIniFile(filePath: string, content: string): void {
  // .ini files are UTF-16LE for MT5
  const buf = Buffer.from('\ufeff' + content, 'utf16le');
  fs.writeFileSync(filePath, buf);
}

/**
 * Write .set file to disk (UTF-16LE encoded)
 */
export function writeSetFile(filePath: string, content: string): void {
  const buf = Buffer.from('\ufeff' + content, 'utf16le');
  fs.writeFileSync(filePath, buf);
}
