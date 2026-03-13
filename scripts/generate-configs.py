#!/usr/bin/env python3
"""
Generate .set and .ini files for all strategy + symbol optimization runs.
5 strategies x 4 symbols x timeframes = config matrix
"""

import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTER_DIR = os.path.join(BASE_DIR, "MQL5", "Profiles", "Tester")

SYMBOLS = ["XAUUSD", "DJ30", "NAS100", "BTCUSD"]
FROM_DATE = "2025.01.01"
TO_DATE = "2026.03.01"

# Timeframe mapping for .ini
TF_MAP = {
    "M3": "M3", "M5": "M5", "M15": "M15", "H1": "H1", "H4": "H4"
}

# HTF enum values for .set files
HTF_ENUM = {
    "H1": 16385,
    "H4": 16388,
    "D1": 16408,
}


def write_utf16le(path, content):
    """Write content as UTF-16LE with BOM"""
    with open(path, 'wb') as f:
        f.write(b'\xff\xfe')
        f.write(content.encode('utf-16-le'))


# ============================================================
# Strategy 1: Session Breakout
# ============================================================
def gen_session_breakout():
    name = "SessionBreakout"
    timeframes = ["M5", "M15"]

    set_content = """; SessionBreakout optimization parameters
InpAsianStart=0||0||0||0||N
InpAsianEnd=8||7||1||9||Y
InpLondonStart=8||7||1||9||Y
InpLondonEnd=11||10||1||12||Y
InpNYStart=13||12||1||14||Y
InpNYEnd=16||15||1||17||Y
InpSessionClose=21||21||0||21||N
InpBreakoutBuffer=5||0||5||20||Y
InpRiskReward=1.5||1.0||0.500000||3.0||Y
InpMinRangePoints=50||20||10||100||Y
InpMaxRangePoints=500||200||100||1000||Y
InpMaxTradesPerDay=2||1||1||3||Y
InpRiskPercent=1.0||1.0||0.000000||1.0||N
InpMagicNumber=100001||100001||0||100001||N
"""

    for sym in SYMBOLS:
        for tf in timeframes:
            write_set(name, sym, tf, set_content)
            write_ini(name, sym, tf)


# ============================================================
# Strategy 2: Mean Reversion BB RSI
# ============================================================
def gen_mean_reversion():
    name = "MeanReversionBBRSI"
    timeframes = ["M5", "M15"]

    set_content = """; MeanReversionBBRSI optimization parameters
InpBB_Period=20||14||2||30||Y
InpBB_Deviation=2.0||1.5||0.500000||3.0||Y
InpRSI_Period=14||7||7||21||Y
InpRSI_BuyLevel=30.0||20.0||5.000000||40.0||Y
InpRSI_SellLevel=70.0||60.0||5.000000||80.0||Y
InpADX_Period=14||10||5||20||Y
InpADX_Threshold=25.0||20.0||5.000000||35.0||Y
InpExitMode=2||1||1||3||Y
InpFixedSL=50||30||10||100||N
InpFixedTP=50||30||10||100||N
InpATR_Period=14||10||5||20||N
InpATR_SL_Mult=1.5||1.0||0.500000||2.5||Y
InpATR_TP_Mult=1.0||0.5||0.500000||2.0||N
InpMaxBarsHold=20||10||10||50||Y
InpRiskPercent=1.0||1.0||0.000000||1.0||N
InpMagicNumber=100002||100002||0||100002||N
"""

    for sym in SYMBOLS:
        for tf in timeframes:
            write_set(name, sym, tf, set_content)
            write_ini(name, sym, tf)


# ============================================================
# Strategy 3: EMA Crossover Pullback
# ============================================================
def gen_ema_crossover():
    name = "EMACrossoverPullback"
    timeframes = ["M5", "M15"]

    # We need separate .set per HTF option (H1 vs H4)
    for htf_name, htf_val in [("H1", HTF_ENUM["H1"]), ("H4", HTF_ENUM["H4"])]:
        set_content = f"""; EMACrossoverPullback optimization parameters (HTF={htf_name})
InpFastEMA=8||5||2||13||Y
InpSlowEMA=21||15||3||30||Y
InpHTF={htf_val}||{htf_val}||0||{htf_val}||N
InpHTF_EMA=50||30||10||100||Y
InpATR_Period=14||10||5||20||N
InpATR_SL_Mult=1.5||1.0||0.500000||3.0||Y
InpATR_TP_Mult=3.0||2.0||1.000000||5.0||Y
InpTrailATR_Mult=1.0||0.5||0.500000||2.0||Y
InpPullbackMode=1||1||1||2||Y
InpRiskPercent=1.0||1.0||0.000000||1.0||N
InpMagicNumber=100003||100003||0||100003||N
"""
        for sym in SYMBOLS:
            for tf in timeframes:
                write_set(name, sym, tf, set_content, suffix=f".{htf_name}")
                write_ini(name, sym, tf, set_suffix=f".{htf_name}")


# ============================================================
# Strategy 4: Momentum Breakout
# ============================================================
def gen_momentum_breakout():
    name = "MomentumBreakout"
    timeframes = ["M5", "M15"]

    set_content = """; MomentumBreakout optimization parameters
InpDonchian_Period=20||10||5||30||Y
InpMACD_Fast=12||8||4||16||Y
InpMACD_Slow=26||20||4||34||Y
InpMACD_Signal=9||5||4||13||Y
InpATR_Period=14||10||5||20||N
InpATR_SL_Mult=2.0||1.0||0.500000||3.0||Y
InpATR_TP_Mult=0.0||0.0||1.000000||5.0||Y
InpATR_Trail_Mult=1.5||1.0||0.500000||3.0||Y
InpATR_Activation=1.0||0.5||0.500000||2.0||Y
InpBreakevenATR=1.0||0.5||0.500000||2.0||Y
InpMomentumFadeBars=3||2||1||5||Y
InpRiskPercent=1.0||1.0||0.000000||1.0||N
InpMagicNumber=100004||100004||0||100004||N
"""

    for sym in SYMBOLS:
        for tf in timeframes:
            write_set(name, sym, tf, set_content)
            write_ini(name, sym, tf)


# ============================================================
# Strategy 5: Order Block FVG
# ============================================================
def gen_order_block_fvg():
    name = "OrderBlockFVG"
    timeframes = ["M5", "M15"]

    for htf_name, htf_val in [("H1", HTF_ENUM["H1"]), ("H4", HTF_ENUM["H4"])]:
        set_content = f"""; OrderBlockFVG optimization parameters (HTF={htf_name})
InpHTF={htf_val}||{htf_val}||0||{htf_val}||N
InpOB_ImpulseATR=1.5||1.0||0.500000||3.0||Y
InpOB_MaxAge=50||30||10||100||Y
InpOB_MaxZones=5||3||1||8||N
InpFVG_Enabled=true||false||0||true||N
InpFVG_MinGapATR=0.3||0.1||0.100000||0.5||Y
InpRSI_Period=14||7||7||21||Y
InpRSI_OB_Level=30.0||25.0||5.000000||40.0||Y
InpRSI_OS_Level=70.0||60.0||5.000000||75.0||Y
InpHTF_EMA=50||30||20||100||Y
InpRiskReward=2.0||1.5||0.500000||3.0||Y
InpSL_Buffer=10||5||5||30||Y
InpUsePartialClose=true||false||0||true||N
InpRiskPercent=1.0||1.0||0.000000||1.0||N
InpMagicNumber=100005||100005||0||100005||N
"""
        for sym in SYMBOLS:
            for tf in timeframes:
                write_set(name, sym, tf, set_content, suffix=f".{htf_name}")
                write_ini(name, sym, tf, set_suffix=f".{htf_name}")


# ============================================================
# Helper functions
# ============================================================
def write_set(ea_name, symbol, tf, content, suffix=""):
    filename = f"{ea_name}.{symbol}.{tf}{suffix}.set"
    path = os.path.join(TESTER_DIR, filename)
    write_utf16le(path, content)
    return filename


def write_ini(ea_name, symbol, tf, set_suffix=""):
    set_filename = f"{ea_name}.{symbol}.{tf}{set_suffix}.set"
    ini_filename = f"{ea_name}.{symbol}.{tf}{set_suffix}.ini"

    ini_content = f"""[Tester]
Expert={ea_name}
ExpertParameters={set_filename}
Symbol={symbol}
Period={tf}
Optimization=2
Model=4
FromDate={FROM_DATE}
ToDate={TO_DATE}
ForwardMode=0
Deposit=10000
Currency=USD
ProfitInPips=0
Leverage=100
ExecutionMode=0
OptimizationCriterion=6
Visual=0
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1
UseRemote=0
UseCloud=0
"""
    path = os.path.join(TESTER_DIR, ini_filename)
    write_utf16le(path, ini_content)
    return ini_filename


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    os.makedirs(TESTER_DIR, exist_ok=True)

    gen_session_breakout()
    gen_mean_reversion()
    gen_ema_crossover()
    gen_momentum_breakout()
    gen_order_block_fvg()

    # Count generated files
    ini_count = len([f for f in os.listdir(TESTER_DIR) if f.endswith('.ini') and not f.startswith('Example')])
    set_count = len([f for f in os.listdir(TESTER_DIR) if f.endswith('.set') and not f.startswith('Example')])

    print(f"Generated {set_count} .set files and {ini_count} .ini files in {TESTER_DIR}")
    print()
    print("Strategies:")
    strategies = {}
    for f in sorted(os.listdir(TESTER_DIR)):
        if f.endswith('.ini') and not f.startswith('Example'):
            parts = f.replace('.ini', '').split('.')
            ea = parts[0]
            if ea not in strategies:
                strategies[ea] = []
            strategies[ea].append(f)

    for ea, files in sorted(strategies.items()):
        print(f"\n  {ea}: {len(files)} configs")
        for f in sorted(files):
            print(f"    {f}")
