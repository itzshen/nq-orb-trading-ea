//+------------------------------------------------------------------+
//|                                        ORB_Breakout_Long.mq5      |
//|                                                                    |
//|  Opening Range Breakout - LONG ONLY                               |
//|                                                                    |
//|  STRATEGY                                                         |
//|  --------                                                         |
//|  1. The first InpORMinutes minutes after the session open define  |
//|     the opening range (OR high / OR low) - always measured from   |
//|     raw M1 data regardless of InpSignalTimeframe below, since M1  |
//|     gives the most precise high/low for whatever window length    |
//|     you choose.                                                   |
//|  2. After the OR window closes, we look for the first candle ON   |
//|     InpSignalTimeframe (default M1; can be M5, M15, etc.) whose   |
//|     CLOSE is above the OR high. Downside breaks are ignored       |
//|     entirely - this version only ever looks for longs. Using a    |
//|     higher signal timeframe than the OR window itself lets you    |
//|     test combos like "15-min OR, confirmed on 5-min closes" or    |
//|     "30-min OR, confirmed on 1-min closes" - for clean behavior,  |
//|     InpORMinutes should be a multiple of InpSignalTimeframe's     |
//|     length (both your example combos satisfy this).               |
//|  3. Entry fills essentially at the open of the candle right after |
//|     the signal candle (we act on the first tick of the new bar,   |
//|     which is effectively that bar's open).                        |
//|  4. Stop loss sits InpSLRangePct of the OR range down from OR     |
//|     high (1.0 = OR low, the original default; 0.5 = range         |
//|     midpoint; etc.). Take profit = InpRR * (entry - SL), i.e.     |
//|     1:1 RR by default - RR is applied the same way regardless of  |
//|     where the SL fraction puts the stop.                          |
//|  5. One trade per broker calendar day (first valid breakout only),|
//|     and only if the breakout happens before the entry cutoff      |
//|     (InpEntryCutoffHourNY/Min, default 11:00am NY) - this narrows  |
//|     entries to the most directional part of the session rather    |
//|     than chasing a late-day break with little runway left. If     |
//|     neither SL nor TP is hit by the separate, later close cutoff   |
//|     (InpCloseCutoffHourNY/Min, default 2:00pm NY), the position is |
//|     force-closed at market - this is an intraday breakout         |
//|     strategy, so trades don't get to carry overnight into the next |
//|     session. A separate close-any-open-position check still runs   |
//|     at the broker-day rollover too, as a safety net in case the    |
//|     close cutoff was ever missed.                                  |
//|  6. Risk InpRiskPercent % of current account equity per trade.    |
//|     Lot size is derived from the stop distance in price points    |
//|     and the symbol's tick value, so this works for any CFD/index  |
//|     symbol without hardcoding a contract multiplier.              |
//|  7. Every trading day gets tagged with a volatility regime (Low/   |
//|     Mid/High tercile, based on a rolling D1 ATR% percentile rank - |
//|     see the VOLATILITY REGIME section below). This is computed    |
//|     and logged/tagged on every trade regardless, but only ENFORCED|
//|     as an entry filter when InpUseVolFilter=true - the default is |
//|     false, so recompiling this doesn't change any existing        |
//|     behavior until you deliberately turn it on.                   |
//|  8. Every trading day ALSO gets tagged with a second, independent  |
//|     regime based on the opening range's own width (see OR-WIDTH   |
//|     REGIME section below) - same diagnostic-first pattern, its own|
//|     InpUseORWidthFilter toggle, can be combined with #7 or tested  |
//|     against it separately.                                        |
//|  9. And a THIRD independent regime, based on the OR window's       |
//|     Kaufman Efficiency Ratio - see EFFICIENCY RATIO REGIME below.  |
//|     OR-width measures MAGNITUDE (how wide was the range); ER       |
//|     measures PATH QUALITY (did price move there cleanly, or        |
//|     whipsaw back and forth) - genuinely different information,     |
//|     not another flavor of the same signal.                         |
//|                                                                    |
//|  INPUTS are grouped in the properties dialog (Opening Range &      |
//|  Signal / Risk & Trade Management / Session Timing / Intraday      |
//|  Cutoffs / the two regime filters / Trade Identification) - use    |
//|  those group headers to navigate rather than scrolling the full    |
//|  flat list.                                                        |
//|                                                                    |
//|  VOLATILITY REGIME TAGGING (diagnostic-first)                     |
//|  -----------------------------------------------                  |
//|  Measure: ATR(InpATRPeriod) on D1 bars, expressed as a % of price  |
//|  (not raw points - normalizes across NQ's wide historical price    |
//|  range). Each day's bucket is computed from data through           |
//|  YESTERDAY's D1 close only (1-day lag, no lookahead), ranked as a  |
//|  percentile against the trailing InpVolLookbackDays (default 252,  |
//|  ~1 trading year) window, then split into Low/Mid/High terciles.   |
//|  Early in your history, before a full lookback window exists, the  |
//|  bucket stays "unknown" (-1) and FAILS OPEN - it never blocks a    |
//|  trade on that basis alone, even with the filter active.           |
//|  Every trade's comment gets tagged with its regime (e.g.           |
//|  "ORB-Long|H72" = High bucket, 72nd percentile) so you can sort or |
//|  filter MT5's own trade history report by regime directly, without|
//|  needing a separate export - do this BEFORE turning InpUseVolFilter|
//|  on, to see whether performance actually differs by bucket in your |
//|  data first. Once you've picked a threshold, set                   |
//|  InpUseVolFilter=true and InpVolFilterMinBucket (0=Low+ i.e. all,   |
//|  1=Mid+High, 2=High only).                                         |
//|                                                                    |
//|  OR-WIDTH REGIME TAGGING (diagnostic-first, independent of above)  |
//|  -----------------------------------------------------------------  |
//|  Measure: today's own OR (high-low), as a % of the OR's midpoint   |
//|  price. No lag needed here - unlike D1 ATR (a whole prior day's    |
//|  measure), the OR width is known live the moment the window closes,|
//|  well before the entry cutoff. KEY DIFFERENCE from the D1 filter:  |
//|  there's no pre-existing broker history for "OR width" to draw on  |
//|  - it only exists because the EA computes it itself, so the        |
//|  rolling lookback history is built LIVE, day by day, starting from |
//|  scratch every time you set a new backtest date range. Until       |
//|  InpORWidthLookbackDays trading days have accumulated within the   |
//|  CURRENT run, the bucket stays "unknown" (-1) and fails open, same |
//|  as the D1 filter's insufficient-history case - just driven by a   |
//|  different cause (fresh accumulation vs. thin broker history).     |
//|  Tagged on the trade comment as e.g. "|OWM55" (OR-width Mid bucket,|
//|  55th percentile), alongside the D1 tag if both are active.        |
//|  Independent toggle: InpUseORWidthFilter. Bounded by a BAND, not   |
//|  just a one-sided threshold: InpORWidthFilterMinBucket AND         |
//|  InpORWidthFilterMaxBucket both apply (default min=1,max=2         |
//|  reproduces the original "Mid+High" min-only behavior). Set        |
//|  min=max=1 to isolate Mid-only, min=max=2 for High-only, etc.       |
//|  ABSOLUTE FLOOR: InpORWidthAbsoluteFloor (default 0.0 = no-op). A   |
//|  percentile rank can only ever say "highest of what's in this      |
//|  window" - it can't detect the whole trailing window being         |
//|  uniformly quiet. If today's raw width% is below this floor, the   |
//|  bucket is force-set to Low regardless of its relative percentile. |
//|                                                                    |
//|  EFFICIENCY RATIO REGIME TAGGING (diagnostic-first, independent)   |
//|  -----------------------------------------------------------------  |
//|  Measure: Kaufman's Efficiency Ratio over the OR window itself -   |
//|  |net close-to-close move across the window| divided by (sum of    |
//|  |bar-to-bar close changes| across the window). Near 1.0 = price    |
//|  moved in a straight line during the OR; near 0 = lots of back-    |
//|  and-forth that net-net went nowhere. Computed in the SAME bar loop|
//|  as ComputeOpeningRange() (no separate scan needed), so - like OR- |
//|  width - it's live and anchored strictly to the 9:30am NY session  |
//|  window, with no lag and no data from outside that window. Same   |
//|  "no pre-existing history, builds live during the run" caveat as   |
//|  OR-width. Tagged on the trade comment as e.g. "|ERH80" (ER High   |
//|  bucket, 80th percentile). Independent toggle: InpUseERFilter,     |
//|  same min/max band pattern as OR-width (InpERFilterMinBucket /     |
//|  InpERFilterMaxBucket).                                            |
//|  ABSOLUTE FLOOR: InpERAbsoluteFloor (default 0.0 = no-op), same     |
//|  reasoning and mechanism as OR-width's floor above.                |
//|                                                                    |
//|  TIMEZONE / SESSION OPEN HANDLING                                 |
//|  ---------------------------------                                |
//|  The broker runs on EU DST (EET/EEST), while the NYSE/Nasdaq open |
//|  is fixed at 9:30am US Eastern time (EST/EDT - US DST). US and EU |
//|  do NOT flip DST on the same dates:                               |
//|    US DST:  2nd Sunday of March  -> 1st Sunday of November        |
//|    EU DST:  last Sunday of March -> last Sunday of October        |
//|  US flips into DST ~2-3 weeks before EU does each spring, and EU  |
//|  flips back to winter time ~1 week before US does each autumn.    |
//|  For most of the actual DST season, BOTH regions are in DST at    |
//|  once and their offsets cancel out, landing back on the same      |
//|  16:30 broker time as winter. The 15:30 open only happens during  |
//|  the narrow windows where US-DST and EU-DST state DISAGREE (that  |
//|  mid/late-March window, and that late-Oct/early-Nov window). So   |
//|  the correct rule is an XOR of the two DST flags, not "is the US  |
//|  in DST" on its own - checking only US DST (an earlier version of |
//|  this logic, and of the original Python backtest, both did this)  |
//|  incorrectly uses 15:30 for the entire April-October stretch.     |
//|  IsUSDST()/IsEUDST() are both DATE-level approximations (they     |
//|  don't model the exact 1am UTC / 2am local cutover instant) -     |
//|  fine for our purposes since transitions land on a low-activity   |
//|  Sunday. Edit the Inp* session inputs below if your actual open   |
//|  times differ.                                                    |
//|                                                                    |
//|  SYMBOL ASSUMPTIONS                                               |
//|  -------------------                                              |
//|  Written for a CFD/index-proxy symbol (e.g. NAS100, USTEC) that   |
//|  trades continuously with no futures-style contract rollover.     |
//|  Assumes NETTING position mode (one position per symbol), which   |
//|  is standard for most CFD/index brokers. If your account is in    |
//|  HEDGING mode you'd need to loop over position tickets instead of |
//|  using PositionSelect() - flag this if that's your setup and I'll |
//|  adjust it.                                                       |
//|                                                                    |
//|  SETUP                                                            |
//|  -----                                                            |
//|  1. Import your CSV as a Custom Symbol (Symbols window -> Create  |
//|     Custom Symbol -> Bars tab -> Import Bars), setting the GMT+2  |
//|     shift correctly during import.                                |
//|  2. Compile this file in MetaEditor (F7).                         |
//|  3. Run it in Strategy Tester against your custom symbol, M1      |
//|     timeframe (the EA reads M1 bars directly regardless of the    |
//|     chart timeframe it's attached to).                            |
//+------------------------------------------------------------------+
#property copyright "ORB Backtest"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUTS ==================

input group "Opening Range & Signal"
input int    InpORMinutes          = 15;    // Opening range length (minutes)
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;  // Timeframe whose candle CLOSE confirms the breakout (M1/M5/M15/...)
input int    InpMinORBars          = 10;    // Minimum M1 bars required inside OR window to trade

input group "Risk & Trade Management"
input double InpRR                 = 1.0;   // Reward:Risk ratio (TP = RR * SL distance)
input double InpSLRangePct         = 1.0;   // SL as a fraction of the OR range, measured down from OR high (1.0 = OR low, 0.5 = midpoint)
input double InpRiskPercent        = 1.0;   // Risk % of account equity per trade

input group "Session Timing (Broker Time, DST-Aware)"
input int    InpSessionOpenHourStd = 16;    // Session open hour, broker time (non-DST)
input int    InpSessionOpenMinStd  = 30;    // Session open minute, broker time (non-DST)
input int    InpSessionOpenHourDst = 15;    // Session open hour, broker time (US DST)
input int    InpSessionOpenMinDst  = 30;    // Session open minute, broker time (US DST)

input group "Intraday Cutoffs (NY Time)"
input int    InpEntryCutoffHourNY  = 11;    // Stop taking new entries at this NY wall clock hour
input int    InpEntryCutoffMinNY   = 0;     // Stop taking new entries at this NY wall clock minute
input int    InpCloseCutoffHourNY  = 14;    // Force-close any still-open position at this NY wall clock hour
input int    InpCloseCutoffMinNY   = 0;     // Force-close any still-open position at this NY wall clock minute

input group "Volatility Regime Filter (Daily ATR%, diagnostic-first)"
input bool   InpUseVolFilter       = false;  // false = diagnostic only (tag trades, don't block any)
input int    InpATRPeriod          = 14;     // ATR period, in days (measured on D1 bars)
input int    InpVolLookbackDays    = 252;    // Rolling window (trading days) for the percentile rank
input int    InpVolFilterMinBucket = 1;      // Minimum bucket required when filter is active: 0=Low,1=Mid,2=High

input group "OR-Width Regime Filter (diagnostic-first)"
input bool   InpUseORWidthFilter       = false;  // false = diagnostic only (tag trades, don't block any)
input int    InpORWidthLookbackDays    = 60;     // Rolling window (trading days, built live during the backtest) for the percentile rank
input int    InpORWidthFilterMinBucket = 1;      // Minimum bucket required when filter is active: 0=Low,1=Mid,2=High
input int    InpORWidthFilterMaxBucket = 2;      // Maximum bucket allowed when filter is active: 0=Low,1=Mid,2=High (default 2 = no upper restriction, reproduces prior min-only behavior)
input double InpORWidthAbsoluteFloor   = 0.0;    // Absolute floor on OR width % - below this, force bucket=Low regardless of relative percentile (0.0 = no floor, true no-op default)

input group "Efficiency Ratio Regime Filter (diagnostic-first)"
input bool   InpUseERFilter       = false;  // false = diagnostic only (tag trades, don't block any)
input int    InpERLookbackDays    = 60;     // Rolling window (trading days, built live during the backtest) for the percentile rank
input int    InpERFilterMinBucket = 1;      // Minimum bucket required when filter is active: 0=Low,1=Mid,2=High
input int    InpERFilterMaxBucket = 2;      // Maximum bucket allowed when filter is active: 0=Low,1=Mid,2=High
input double InpERAbsoluteFloor   = 0.0;    // Absolute floor on ER (0-1 scale) - below this, force bucket=Low regardless of relative percentile (0.0 = no floor, true no-op default)

input group "Trade Identification"
input ulong  InpMagicNumber        = 20260722;
input string InpTradeComment       = "ORB-Long";

//================== STATE (per trading day) ==================
datetime g_dayStart        = 0;      // midnight of the broker calendar date currently tracked
datetime g_sessionOpenTime = 0;
datetime g_orEndTime       = 0;
datetime g_entryCutoffTime = 0;   // stop taking new entries at/after this time, broker time
datetime g_closeCutoffTime = 0;   // force-close any open position at/after this time, broker time
double   g_orHigh          = 0.0;
double   g_orLow           = 0.0;
bool     g_orValid         = false;  // false if the OR window didn't have enough bars
bool     g_orComputed      = false;  // whether we've already computed the OR for today
bool     g_tradedToday     = false;
datetime g_lastSeenBarTime = 0;
datetime g_lastSeenSignalBarTime = 0;   // last-seen bar-open-time on InpSignalTimeframe (not reset daily)

int      g_atrHandle    = INVALID_HANDLE;   // D1 ATR indicator handle, created once in OnInit
int      g_volBucket    = -1;               // today's regime: -1=unknown/insufficient history, 0=Low, 1=Mid, 2=High
double   g_volPercentile = -1.0;            // today's ATR% rolling percentile rank (0-100)
double   g_volATRPct    = -1.0;             // yesterday's ATR as a % of price (the raw measure behind the rank)

double   g_orWidthHistory[];                // rolling, LIVE-built history of past days' OR width (% of price) -
                                             // unlike D1 ATR, this has no pre-existing broker history to draw on;
                                             // it only accumulates as the backtest itself progresses (see header)
int      g_orWidthBucket     = -1;          // today's regime: -1=unknown/insufficient history, 0=Low, 1=Mid, 2=High
double   g_orWidthPercentile = -1.0;
double   g_orWidthPct        = -1.0;        // today's OR width as a % of the OR's own midpoint price

double   g_orEfficiencyRatio = -1.0;        // today's raw OR-window efficiency ratio (0-1), computed inside
                                             // ComputeOpeningRange() itself (same bar loop, no duplicate scan)
double   g_erHistory[];                     // rolling, LIVE-built history - same "no pre-existing source" caveat as OR-width
int      g_erBucket     = -1;               // today's regime: -1=unknown/insufficient history, 0=Low, 1=Mid, 2=High
double   g_erPercentile = -1.0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   g_lastSeenBarTime = 0;
   g_dayStart = 0;          // sentinel value forces a state rebuild on the first tick
   ArrayResize(g_orWidthHistory, 0);   // fresh rolling history each run - see header re: no pre-existing source for this
   ArrayResize(g_erHistory, 0);        // same, for the Efficiency Ratio filter

   g_atrHandle = iATR(_Symbol, PERIOD_D1, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      PrintFormat("WARNING: Failed to create D1 ATR handle (error %d) - volatility regime will stay "
                  "'unknown' for every day, which fails OPEN (doesn't block trades) even with "
                  "InpUseVolFilter=true. Check symbol/history availability.", GetLastError());

   int entryCutoffMin = InpEntryCutoffHourNY * 60 + InpEntryCutoffMinNY;
   int closeCutoffMin = InpCloseCutoffHourNY * 60 + InpCloseCutoffMinNY;
   if(entryCutoffMin >= closeCutoffMin)
      PrintFormat("WARNING: InpEntryCutoffHourNY:InpEntryCutoffMinNY (%02d:%02d NY) is at or after "
                  "InpCloseCutoffHourNY:InpCloseCutoffMinNY (%02d:%02d NY) - new trades would never "
                  "get any runway before being force-closed. Check your inputs.",
                  InpEntryCutoffHourNY, InpEntryCutoffMinNY, InpCloseCutoffHourNY, InpCloseCutoffMinNY);

   if(InpORWidthFilterMinBucket > InpORWidthFilterMaxBucket)
      PrintFormat("WARNING: InpORWidthFilterMinBucket (%d) is greater than InpORWidthFilterMaxBucket (%d) - "
                  "this band can never be satisfied, so with InpUseORWidthFilter=true every day would be "
                  "blocked. Check your inputs.", InpORWidthFilterMinBucket, InpORWidthFilterMaxBucket);

   if(InpERFilterMinBucket > InpERFilterMaxBucket)
      PrintFormat("WARNING: InpERFilterMinBucket (%d) is greater than InpERFilterMaxBucket (%d) - "
                  "this band can never be satisfied, so with InpUseERFilter=true every day would be "
                  "blocked. Check your inputs.", InpERFilterMinBucket, InpERFilterMaxBucket);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime latestBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(latestBarTime == g_lastSeenBarTime) return;   // only act once per new M1 bar
   g_lastSeenBarTime = latestBarTime;

   // Evaluate the bar that just fully closed (shift 1). If we act on a
   // signal here, the market order fills essentially at the open of the
   // bar now forming (shift 0) - matching "entry at open of next candle".
   datetime closedBarTime = iTime(_Symbol, PERIOD_M1, 1);
   if(closedBarTime <= 0) return;

   datetime closedBarDay = DateFloor(closedBarTime);

   // ---- new broker calendar day -> force-close any leftover position, reset state ----
   if(closedBarDay != g_dayStart)
   {
      CloseOpenPositionIfAny();
      InitDailyState(closedBarDay);
   }

   if(closedBarTime < g_sessionOpenTime) return;   // before today's session open, nothing to do yet

   // ---- Force-close any still-open position at/after the close cutoff.  ----
   // ---- Runs every bar past the cutoff; CloseOpenPositionIfAny is a      ----
   // ---- no-op once there's nothing left open, so this is cheap.         ----
   if(closedBarTime >= g_closeCutoffTime)
   {
      CloseOpenPositionIfAny();
   }

   // ---- Step 1: once we cross the OR window end, compute OR high/low from history ----
   if(!g_orComputed && closedBarTime >= g_orEndTime)
   {
      ComputeOpeningRange();
      g_orComputed = true;
      UpdateORWidthHistory();          // needs today's own OR, so this can't run until here (unlike the D1 filter)
      UpdateEfficiencyRatioHistory();  // same reasoning - needs today's own OR-window price path
   }

   if(!g_orComputed || !g_orValid || g_tradedToday) return;
   if(closedBarTime < g_orEndTime) return;           // still inside the OR window itself
   if(closedBarTime >= g_entryCutoffTime) return;     // past the entry cutoff - don't open new trades this late

   // Volatility regime gate: only enforced when InpUseVolFilter is true. An
   // unknown bucket (-1, insufficient rolling history) always fails OPEN -
   // it never blocks a trade, even with the filter on.
   if(InpUseVolFilter && g_volBucket != -1 && g_volBucket < InpVolFilterMinBucket) return;

   // OR-width regime gate: same fail-open behavior as above, independent toggle.
   // Min/max together form a band (e.g. min=max=1 isolates Mid-only), not just
   // a one-sided threshold - default max=2 reproduces the original min-only behavior.
   if(InpUseORWidthFilter && g_orWidthBucket != -1 &&
      (g_orWidthBucket < InpORWidthFilterMinBucket || g_orWidthBucket > InpORWidthFilterMaxBucket)) return;

   // Efficiency Ratio regime gate: same fail-open / band pattern, independent toggle.
   if(InpUseERFilter && g_erBucket != -1 &&
      (g_erBucket < InpERFilterMinBucket || g_erBucket > InpERFilterMaxBucket)) return;

   // ---- Step 2: first InpSignalTimeframe candle that CLOSES above the OR high triggers the long ----
   // We're still driven by M1 ticks (OnTick only fires this far once per new M1
   // bar), but we only want to evaluate once a fresh bar on InpSignalTimeframe
   // has appeared - i.e. once its predecessor (shift 1) has actually closed.
   datetime latestSignalBarTime = iTime(_Symbol, InpSignalTimeframe, 0);
   if(latestSignalBarTime != g_lastSeenSignalBarTime)
   {
      g_lastSeenSignalBarTime = latestSignalBarTime;
      datetime closedSignalBarTime = iTime(_Symbol, InpSignalTimeframe, 1);

      // Only count a signal bar that STARTED at/after the OR window ended -
      // this skips any bar that straddles the OR window and the post-OR
      // period (relevant if InpORMinutes isn't a clean multiple of the
      // signal timeframe's length). See header comment.
      if(closedSignalBarTime >= g_orEndTime)
      {
         double closedSignalClose = iClose(_Symbol, InpSignalTimeframe, 1);
         if(closedSignalClose > g_orHigh)
         {
            EnterLong();
            g_tradedToday = true;   // one trade per day, regardless of whether the order actually filled
         }
      }
   }
}

//+------------------------------------------------------------------+
//  Reset all per-day tracking state for a new broker calendar day
//+------------------------------------------------------------------+
void InitDailyState(datetime dayStart)
{
   g_dayStart    = dayStart;
   g_orHigh      = 0.0;
   g_orLow       = 0.0;
   g_orValid     = false;
   g_orComputed  = false;
   g_tradedToday = false;

   MqlDateTime dt;
   TimeToStruct(dayStart, dt);

   bool usDst = IsUSDST(dt.year, dt.mon, dt.day);
   bool euDst = IsEUDST(dt.year, dt.mon, dt.day);
   // 15:30 open only applies when US-DST and EU-DST states DISAGREE (the
   // narrow mismatch windows in spring/autumn). When both regions are in
   // the same state - including nearly all of actual summer - the two
   // offsets cancel and it's 16:30, same as winter. See header comment.
   bool useDstOpen = (usDst != euDst);
   int openHour = useDstOpen ? InpSessionOpenHourDst : InpSessionOpenHourStd;
   int openMin  = useDstOpen ? InpSessionOpenMinDst  : InpSessionOpenMinStd;

   g_sessionOpenTime = dayStart + openHour * 3600 + openMin * 60;
   g_orEndTime        = g_sessionOpenTime + InpORMinutes * 60;

   // Both cutoffs are expressed as NY wall-clock times, converted to an offset
   // in minutes from 9:30am NY (the session open). Deriving them this way
   // means they automatically inherit g_sessionOpenTime's correct US/EU DST
   // handling instead of needing their own separate DST calculation.
   int entryCutoffMinutesAfterOpen = (InpEntryCutoffHourNY * 60 + InpEntryCutoffMinNY) - (9 * 60 + 30);
   int closeCutoffMinutesAfterOpen = (InpCloseCutoffHourNY * 60 + InpCloseCutoffMinNY) - (9 * 60 + 30);
   g_entryCutoffTime = g_sessionOpenTime + entryCutoffMinutesAfterOpen * 60;
   g_closeCutoffTime = g_sessionOpenTime + closeCutoffMinutesAfterOpen * 60;

   ComputeVolatilityRegime(dayStart);
}

//+------------------------------------------------------------------+
//  Tag today with a volatility regime bucket, using only data through
//  YESTERDAY's D1 close (1-day lag - no lookahead into today's still-
//  forming price action). Measure: ATR(InpATRPeriod) on D1, expressed
//  as a % of price (so it's comparable across NQ's wide historical
//  price range rather than comparing raw point values). Bucket: where
//  yesterday's ATR% ranks within the trailing InpVolLookbackDays window
//  (itself included in the window it's ranked against), split into
//  terciles. Diagnostic-first: this always runs and tags every trade's
//  comment, regardless of whether InpUseVolFilter is on.
//+------------------------------------------------------------------+
void ComputeVolatilityRegime(datetime dayStart)
{
   g_volBucket     = -1;
   g_volPercentile = -1.0;
   g_volATRPct     = -1.0;

   if(g_atrHandle == INVALID_HANDLE) return;

   // Shift of the most recent D1 bar that opened strictly before today -
   // i.e. "yesterday" (or the last trading day before a weekend/holiday gap).
   int shiftYesterday = iBarShift(_Symbol, PERIOD_D1, dayStart - 1, false);
   if(shiftYesterday < 0) return;

   int needed = InpVolLookbackDays;
   int totalBars = iBars(_Symbol, PERIOD_D1);
   if(totalBars - shiftYesterday < needed) return;   // not enough trailing history yet - stays "unknown"

   double atrBuf[], closeBuf[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(closeBuf, true);

   if(CopyBuffer(g_atrHandle, 0, shiftYesterday, needed, atrBuf) != needed) return;
   if(CopyClose(_Symbol, PERIOD_D1, shiftYesterday, needed, closeBuf) != needed) return;

   double atrPct[];
   ArrayResize(atrPct, needed);
   for(int i = 0; i < needed; i++)
      atrPct[i] = (closeBuf[i] > 0) ? (atrBuf[i] / closeBuf[i]) * 100.0 : 0.0;

   double currentATRPct = atrPct[0];   // index 0 = most recent = yesterday, since series-ordered

   int countLE = 0;
   for(int i = 0; i < needed; i++)
      if(atrPct[i] <= currentATRPct) countLE++;

   double pct = (double)countLE / (double)needed * 100.0;

   int bucket;
   if(pct < 33.333) bucket = 0;         // Low
   else if(pct < 66.667) bucket = 1;    // Mid
   else bucket = 2;                     // High

   g_volATRPct     = currentATRPct;
   g_volPercentile = pct;
   g_volBucket     = bucket;

   MqlDateTime dt;
   TimeToStruct(dayStart, dt);
   PrintFormat("Vol regime %04d.%02d.%02d: ATR%%=%.3f, percentile=%.1f, bucket=%s (lookback=%d days)",
               dt.year, dt.mon, dt.day, g_volATRPct, g_volPercentile, BucketLabel(g_volBucket), needed);
}

string BucketLabel(int bucket)
{
   if(bucket == 0) return "Low";
   if(bucket == 1) return "Mid";
   if(bucket == 2) return "High";
   return "Unknown";
}

string BucketShortCode(int bucket)
{
   if(bucket == 0) return "L";
   if(bucket == 1) return "M";
   if(bucket == 2) return "H";
   return "U";
}

//+------------------------------------------------------------------+
//  Compute OR high/low directly from history over [sessionOpen, orEnd)
//  (queried fresh each time rather than accumulated tick-by-tick, so
//  it's correct even after an EA restart mid-session). Also computes
//  the OR-window's Kaufman Efficiency Ratio (net move / total path
//  length of closes) in the SAME pass, since it needs the same bar
//  range - avoids a second iBarShift/scan just for that.
//+------------------------------------------------------------------+
void ComputeOpeningRange()
{
   int shiftOpen = iBarShift(_Symbol, PERIOD_M1, g_sessionOpenTime, false);
   int shiftEnd  = iBarShift(_Symbol, PERIOD_M1, g_orEndTime, false);

   double hi = -1.0, lo = -1.0;
   int count = 0;

   int lo_shift = MathMin(shiftEnd, shiftOpen);
   int hi_shift = MathMax(shiftEnd, shiftOpen);

   // Note: this loop visits bars in REVERSE chronological order (shift 0 =
   // most recent, so increasing shift moves further into the past - lo_shift
   // sits nearest g_orEndTime, hi_shift nearest g_sessionOpenTime). That's
   // irrelevant for high/low (order-independent), and for the ER path-length
   // sum (|a-b|=|b-a|, so summing adjacent-pair diffs doesn't care about
   // direction) - it only matters for correctly labeling which end is
   // chronologically "first" vs "last", handled explicitly below.
   double firstChronClose = 0.0;   // overwritten every valid iteration; final value = chronologically FIRST bar's close
   double lastChronClose  = 0.0;   // set once, on the loop's first valid iteration = chronologically LAST bar's close
   bool   haveLast = false;
   double prevClose = 0.0;
   bool   havePrev = false;
   double pathSum = 0.0;

   for(int shift = lo_shift; shift <= hi_shift; shift++)
   {
      if(shift < 0) continue;
      datetime t = iTime(_Symbol, PERIOD_M1, shift);
      if(t < g_sessionOpenTime || t >= g_orEndTime) continue;   // ground-truth window filter

      double h = iHigh(_Symbol, PERIOD_M1, shift);
      double l = iLow(_Symbol, PERIOD_M1, shift);
      double c = iClose(_Symbol, PERIOD_M1, shift);

      if(hi < 0 || h > hi) hi = h;
      if(lo < 0 || l < lo) lo = l;

      if(!haveLast) { lastChronClose = c; haveLast = true; }
      firstChronClose = c;

      if(havePrev) pathSum += MathAbs(c - prevClose);
      prevClose = c;
      havePrev = true;

      count++;
   }

   if(count < InpMinORBars || hi <= 0 || lo <= 0 || hi <= lo)
   {
      g_orValid = false;
      g_orEfficiencyRatio = -1.0;
      return;
   }

   g_orHigh  = hi;
   g_orLow   = lo;
   g_orValid = true;

   double netMove = MathAbs(lastChronClose - firstChronClose);
   g_orEfficiencyRatio = (pathSum > 0) ? (netMove / pathSum) : 0.0;   // 0 path length -> no movement at all -> ER=0
}

//+------------------------------------------------------------------+
//  Tag today with an OR-width regime bucket, using today's OWN just-
//  computed OR (no lag needed - unlike the D1 ATR filter, the OR width
//  is known live the moment the window closes, well before the entry
//  cutoff). Measure: OR width as a % of the OR's own midpoint price.
//  Unlike D1 ATR, there's no pre-existing broker history to draw on for
//  this - "OR width" only exists because we compute it ourselves each
//  day, so the rolling history builds up FROM SCRATCH every time you
//  run a new backtest range. Until InpORWidthLookbackDays trading days
//  have accumulated within THIS run, the bucket stays "unknown" (-1)
//  and fails open, same as the D1 filter's insufficient-history case.
//+------------------------------------------------------------------+
void UpdateORWidthHistory()
{
   g_orWidthBucket     = -1;
   g_orWidthPercentile = -1.0;
   g_orWidthPct        = -1.0;

   if(!g_orValid) return;   // don't pollute the rolling history with an invalid/insufficient OR day

   double mid = (g_orHigh + g_orLow) / 2.0;
   if(mid <= 0) return;
   double todayWidthPct = (g_orHigh - g_orLow) / mid * 100.0;

   int n = ArraySize(g_orWidthHistory);
   ArrayResize(g_orWidthHistory, n + 1);
   g_orWidthHistory[n] = todayWidthPct;
   n++;

   int needed = InpORWidthLookbackDays;
   if(n < needed) return;   // not enough live-accumulated history yet - stays "unknown"

   int startIdx = n - needed;
   int countLE = 0;
   for(int i = startIdx; i < n; i++)
      if(g_orWidthHistory[i] <= todayWidthPct) countLE++;

   double pct = (double)countLE / (double)needed * 100.0;

   int bucket;
   if(pct < 33.333) bucket = 0;         // Low
   else if(pct < 66.667) bucket = 1;    // Mid
   else bucket = 2;                     // High

   // Absolute floor override: a pure percentile rank can only ever say
   // "highest of what's in this window" - it can't detect the whole window
   // being uniformly quiet. If today's raw width% is below the floor, force
   // Low regardless of its relative rank. Default 0.0 is a true no-op (OR
   // width is always > 0 for any valid day).
   bool floorApplied = (todayWidthPct < InpORWidthAbsoluteFloor);
   if(floorApplied) bucket = 0;

   g_orWidthPct        = todayWidthPct;
   g_orWidthPercentile = pct;
   g_orWidthBucket     = bucket;

   MqlDateTime dt;
   TimeToStruct(g_dayStart, dt);
   PrintFormat("OR-width regime %04d.%02d.%02d: width%%=%.3f, percentile=%.1f, bucket=%s (lookback=%d days)%s",
               dt.year, dt.mon, dt.day, g_orWidthPct, g_orWidthPercentile, BucketLabel(g_orWidthBucket), needed,
               floorApplied ? " [FLOOR APPLIED - forced Low]" : "");
}

//+------------------------------------------------------------------+
//  Tag today with an Efficiency Ratio regime bucket, using today's OWN
//  OR-window efficiency ratio (computed in ComputeOpeningRange(), no
//  lag needed - same reasoning as OR-width). ER = |net close-to-close
//  move across the OR window| / (sum of |bar-to-bar close changes|
//  across the OR window) - a value near 1.0 means price moved in a
//  straight line during the OR; near 0 means lots of back-and-forth
//  that net-net went nowhere. Same "no pre-existing history, builds
//  live" caveat as OR-width applies here too.
//+------------------------------------------------------------------+
void UpdateEfficiencyRatioHistory()
{
   g_erBucket     = -1;
   g_erPercentile = -1.0;

   if(!g_orValid || g_orEfficiencyRatio < 0) return;   // don't pollute history with an invalid/insufficient OR day

   double todayER = g_orEfficiencyRatio;

   int n = ArraySize(g_erHistory);
   ArrayResize(g_erHistory, n + 1);
   g_erHistory[n] = todayER;
   n++;

   int needed = InpERLookbackDays;
   if(n < needed) return;   // not enough live-accumulated history yet - stays "unknown"

   int startIdx = n - needed;
   int countLE = 0;
   for(int i = startIdx; i < n; i++)
      if(g_erHistory[i] <= todayER) countLE++;

   double pct = (double)countLE / (double)needed * 100.0;

   int bucket;
   if(pct < 33.333) bucket = 0;         // Low
   else if(pct < 66.667) bucket = 1;    // Mid
   else bucket = 2;                     // High

   // Absolute floor override: same reasoning as OR-width - a pure percentile
   // rank can't detect the whole trailing window being uniformly choppy.
   // Default 0.0 is a true no-op (ER is always >= 0 by construction).
   bool floorApplied = (todayER < InpERAbsoluteFloor);
   if(floorApplied) bucket = 0;

   g_erPercentile = pct;
   g_erBucket     = bucket;

   MqlDateTime dt2;
   TimeToStruct(g_dayStart, dt2);
   PrintFormat("Efficiency Ratio regime %04d.%02d.%02d: ER=%.4f, percentile=%.1f, bucket=%s (lookback=%d days)%s",
               dt2.year, dt2.mon, dt2.day, todayER, g_erPercentile, BucketLabel(g_erBucket), needed,
               floorApplied ? " [FLOOR APPLIED - forced Low]" : "");
}

//+------------------------------------------------------------------+
//  US DST check: 2nd Sunday of March through 1st Sunday of November
//  (the US DST rule in effect since 2007). Date-level approximation -
//  see the header comment for what that means in practice.
//+------------------------------------------------------------------+
bool IsUSDST(int year, int mon, int day)
{
   datetime dstStart = NthSundayOfMonth(year, 3, 2);
   datetime dstEnd    = NthSundayOfMonth(year, 11, 1);
   datetime checkDate = StringToTime(StringFormat("%04d.%02d.%02d 12:00", year, mon, day));
   return (checkDate >= dstStart && checkDate < dstEnd);
}

datetime NthSundayOfMonth(int year, int month, int n)
{
   datetime firstOfMonth = StringToTime(StringFormat("%04d.%02d.01 00:00", year, month));
   MqlDateTime dt;
   TimeToStruct(firstOfMonth, dt);
   int dow = dt.day_of_week;                    // 0 = Sunday .. 6 = Saturday
   int firstSundayDay = 1 + ((7 - dow) % 7);
   int targetDay = firstSundayDay + (n - 1) * 7;
   return StringToTime(StringFormat("%04d.%02d.%02d 12:00", year, month, targetDay));
}

//+------------------------------------------------------------------+
//  EU DST check: last Sunday of March through last Sunday of October
//  (EU Directive 2000/84/EC). Date-level approximation, same caveat
//  as IsUSDST() above.
//+------------------------------------------------------------------+
bool IsEUDST(int year, int mon, int day)
{
   datetime dstStart = LastSundayOfMonth(year, 3);
   datetime dstEnd    = LastSundayOfMonth(year, 10);
   datetime checkDate = StringToTime(StringFormat("%04d.%02d.%02d 12:00", year, mon, day));
   return (checkDate >= dstStart && checkDate < dstEnd);
}

datetime LastSundayOfMonth(int year, int month)
{
   int nextMonth = month + 1;
   int nextYear  = year;
   if(nextMonth > 12) { nextMonth = 1; nextYear++; }

   datetime firstOfNextMonth = StringToTime(StringFormat("%04d.%02d.01 00:00", nextYear, nextMonth));
   datetime lastDayOfMonth   = firstOfNextMonth - 86400;   // one day before the 1st of next month

   MqlDateTime dt;
   TimeToStruct(lastDayOfMonth, dt);
   int dow = dt.day_of_week;                    // 0 = Sunday .. 6 = Saturday
   datetime lastSunday = lastDayOfMonth - dow * 86400;

   MqlDateTime dt2;
   TimeToStruct(lastSunday, dt2);
   return StringToTime(StringFormat("%04d.%02d.%02d 12:00", dt2.year, dt2.mon, dt2.day));
}

//+------------------------------------------------------------------+
datetime DateFloor(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
void EnterLong()
{
   if(PositionSelect(_Symbol)) return;   // safety net: never stack positions

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // SL sits InpSLRangePct of the OR range down from OR high. InpSLRangePct=1.0
   // reproduces the original "SL at OR low" behavior; 0.5 puts it at the
   // range's midpoint, etc.
   double orRange = g_orHigh - g_orLow;
   double sl = g_orHigh - InpSLRangePct * orRange;

   double riskPts = ask - sl;
   if(riskPts <= 0) return;

   double tp = ask + InpRR * riskPts;

   double lots = CalculateLotSize(riskPts);
   if(lots <= 0) return;

   // Tag the regime(s) onto the trade comment (e.g. "ORB-Long|H72|OWM55" = D1
   // vol High bucket/72nd pct, OR-width Mid bucket/55th pct) so both show up
   // directly in the Strategy Tester's trade history/report - no separate
   // export or cross-referencing needed to do the tercile breakdown.
   string comment = InpTradeComment;
   if(g_volBucket != -1)
      comment = comment + "|" + BucketShortCode(g_volBucket) + IntegerToString((int)MathRound(g_volPercentile));
   if(g_orWidthBucket != -1)
      comment = comment + "|OW" + BucketShortCode(g_orWidthBucket) + IntegerToString((int)MathRound(g_orWidthPercentile));
   if(g_erBucket != -1)
      comment = comment + "|ER" + BucketShortCode(g_erBucket) + IntegerToString((int)MathRound(g_erPercentile));

   trade.Buy(lots, _Symbol, 0.0, sl, tp, comment);
}

//+------------------------------------------------------------------+
//  Fixed-fractional position sizing: risk InpRiskPercent% of current
//  equity, sized off the actual SL distance and the symbol's tick
//  value - works for any CFD/index symbol without a hardcoded
//  contract multiplier.
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPts)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;

   double valuePerPriceUnit = tickValue / tickSize;   // account-currency value of a 1.0 price move, per 1 lot
   double lots = riskAmount / (riskPts * valuePerPriceUnit);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = minLot;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
}

//+------------------------------------------------------------------+
void CloseOpenPositionIfAny()
{
   if(PositionSelect(_Symbol))
   {
      if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
         trade.PositionClose(_Symbol);
   }
}
//+------------------------------------------------------------------+